// SPDX-License-Identifier: MIT
// Copyright (c) 2025 Morpho Association
pragma solidity 0.8.37;

import {IMidnight, Offer, Market} from "../../lib/midnight/src/interfaces/IMidnight.sol";
import {IRatifier} from "../../lib/midnight/src/interfaces/IRatifier.sol";
import {IdLib} from "../../lib/midnight/src/libraries/IdLib.sol";
import {CALLBACK_SUCCESS} from "../../lib/midnight/src/libraries/ConstantsLib.sol";
import {IERC20} from "../interfaces/IERC20.sol";
import {SafeERC20Lib} from "../libraries/SafeERC20Lib.sol";
import {MathLib} from "../libraries/MathLib.sol";
import {WAD} from "../libraries/ConstantsLib.sol";
import {IVaultV2} from "../interfaces/IVaultV2.sol";
import {IMidnightAdapterBase, IMidnightAdapterStaticTyping, MarketData} from "./interfaces/IMidnightAdapter.sol";
import {DurationsLib} from "./libraries/DurationsLib.sol";

/// VALUATION
/// @dev Approximates held assets by discounting the net credit of each market at a constant simple net rate until maturity.
/// @dev Rate is rounded down. Interest excluded from the rate is realized immediately.
/// @dev Losses are immediately accounted in realAssets() minus a discount applied to the remaining interest to be earned, in proportion to the relative sizes of the loss and the adapter's position in the market hit by the loss.
///
/// ROLES
/// @dev The adapter must have the allocator role in its parent vault to buy.
/// @dev The adapter must have the allocator or sentinel role to withdraw to the vault and to sell (except through forceDeallocate).
/// @dev Sub-ratifiers define which offers are authorized.
/// @dev The sentinel can only remove sub-ratifiers.
///
/// BUYING
/// @dev Buy offers must set callbackData (takes of sell offers must set takerCallbackData) to abi.encode(adapter, data) to select where the liquidity will be deallocated, to abi.encode(address(0), "") to pull the liquidity from the vault's idle funds, or to abi.encode(address(this), market) to withdraw from a Midnight market on the adapter.
/// @dev For self-funding, data is abi.encode(fundingMarket).
///
/// SELLING
/// @dev A sale has a shortfall when the proceeds are less than the amortized value of the sold net credit.
/// @dev A shortfall decreases the rate, so the amortized value of the market decreases only by the received assets.
/// @dev Bad debt that is visible in onSell is applied before the shortfall.
/// @dev This includes bad debt realized during the sale (e.g. in the buyer callback), which then overvalues the market by at most the shortfall right after the sale, and by zero at maturity.
///
/// ALLOCATOR GUARDRAILS
/// @dev minNetRate, noSalesBelowFaceValue and noSalesWithShortfall help the curator set guardrails for allocators.
/// @dev Changing these parameters is not timelocked, because they are not used to provide guarantees to depositors.
/// @dev Sales in forceSellable markets ignore minNetRate, but not noSalesBelowFaceValue and noSalesWithShortfall.
///
/// DURATION CAPS
/// @dev Durations can be used to cap the amount of credit above specific TTMs.
/// @dev The caps of a duration are the vault's caps of the id keccak256(abi.encode("this/duration", adapter, duration)).
/// @dev A position counts toward every duration <= its current remaining time to maturity.
/// @dev The vault does not store the allocations of duration ids. The adapter stores them instead and enforces the caps as well.
/// @dev The adapter checks these caps against the stored net credit, which is an upper bound of the exposure at each check.
/// @dev Unlike the vault's ids, duration ids do not require a non-zero allocation on deallocation.
/// @dev A duration of 0 can effectively always be used, through adapterId, since it means capping all Midnight markets.
///
/// TIMELOCKS
/// @dev Before adding the adapter to the vault, its timelocks must be properly set.
/// @dev The system is the same as the one used in VaultV2. Dev comments in VaultV2.sol on timelocks also apply here.
contract MidnightAdapter is IMidnightAdapterStaticTyping {
    using MathLib for uint256;
    using MathLib for uint128;
    using MathLib for uint48;
    using DurationsLib for bytes32;

    /* CONSTANTS */

    /// @dev Fillable with dust takes.
    uint256 public constant MAX_MARKETS = 250;

    /* IMMUTABLES */

    address public immutable asset;
    address public immutable parentVault;
    address public immutable midnight;
    bytes32 public immutable adapterId;
    /// @dev Sorted in ascending order.
    bytes32 public immutable packedDurations;
    uint256 public immutable durationsLength;

    /* TRANSIENT STORAGE */

    bytes32 transient overriddenMarketId;
    uint256 transient overriddenMarketNetCredit;

    /* TIMELOCKS STORAGE */

    mapping(bytes4 selector => uint256) public timelock;
    mapping(bytes4 selector => bool) public abdicated;
    mapping(bytes data => uint256) public executableAt;

    /* ADAPTER STORAGE */

    address public skimRecipient;
    mapping(address subRatifier => bool) public isSubRatifier;

    bytes32[] public marketIds;
    /// @dev Net credit last reported to the vault's caps.
    mapping(bytes32 marketId => MarketData) public marketData;

    uint32 public maxTtm;
    /// @dev Minimum net rate of a market after a maker or taker buy, or after a loss sale.
    uint64 public minNetRate;
    bool public noSalesWithShortfall;
    bool public noSalesBelowFaceValue;

    /* CONSTRUCTOR */

    constructor(address _parentVault, address _midnight, uint256[] memory _durations) {
        asset = IVaultV2(_parentVault).asset();
        parentVault = _parentVault;
        midnight = _midnight;
        IMidnight(_midnight).setIsAuthorized(address(this), true, address(this));
        adapterId = keccak256(abi.encode("this", address(this)));

        packedDurations = DurationsLib.pack(_durations);
        durationsLength = _durations.length;
    }

    /* MULTICALL */

    /// @dev Useful for EOAs to batch curator and allocator calls.
    /// @dev Does not return anything, because accounts who would use the return data would be contracts, which can do the multicall themselves.
    function multicall(bytes[] calldata data) external {
        for (uint256 i = 0; i < data.length; i++) {
            (bool success, bytes memory returnData) = address(this).delegatecall(data[i]);
            if (!success) {
                assembly ("memory-safe") {
                    revert(add(32, returnData), mload(returnData))
                }
            }
        }
    }

    /* TIMELOCK FUNCTIONS */

    /// @dev Will revert if the timelock value is type(uint256).max or any value that overflows when added to the block timestamp.
    function submit(bytes calldata data) external {
        require(msg.sender == IVaultV2(parentVault).curator(), NotAuthorized());
        require(executableAt[data] == 0, DataAlreadyPending());

        // forge-lint: disable-next-item(unsafe-typecast) we explicitly want only the first bytes4.
        bytes4 selector = bytes4(data);
        // Exact length so that onBuy can find pending setForceSellable calls.
        require(selector != IMidnightAdapterBase.setForceSellable.selector || data.length == 36, InvalidLength());
        // forge-lint: disable-next-item(unsafe-typecast) we explicitly want only the second bytes4.
        uint256 _timelock = selector == IMidnightAdapterBase.decreaseTimelock.selector
            ? timelock[bytes4(data[4:8])]
            : timelock[selector];
        executableAt[data] = block.timestamp + _timelock;
        emit Submit(selector, data, executableAt[data]);
    }

    function timelocked() internal {
        // forge-lint: disable-next-item(unsafe-typecast) we explicitly want only the first bytes4.
        bytes4 selector = bytes4(msg.data);
        require(executableAt[msg.data] != 0, DataNotTimelocked());
        require(block.timestamp >= executableAt[msg.data], TimelockNotExpired());
        require(!abdicated[selector], Abdicated());
        executableAt[msg.data] = 0;
        emit Accept(selector, msg.data);
    }

    function revoke(bytes calldata data) external {
        require(
            msg.sender == IVaultV2(parentVault).curator() || IVaultV2(parentVault).isSentinel(msg.sender),
            NotAuthorized()
        );
        require(executableAt[data] != 0, DataNotTimelocked());
        executableAt[data] = 0;
        // forge-lint: disable-next-item(unsafe-typecast) we explicitly want only the first bytes4.
        bytes4 selector = bytes4(data);
        emit Revoke(msg.sender, selector, data);
    }

    /// @dev This function requires great caution because it can irreversibly disable submit for a selector.
    /// @dev Existing pending operations submitted before increasing a timelock can still be executed at the initial executableAt.
    function increaseTimelock(bytes4 selector, uint256 newDuration) external {
        timelocked();
        require(selector != IMidnightAdapterBase.decreaseTimelock.selector, AutomaticallyTimelocked());
        require(newDuration >= timelock[selector], TimelockNotIncreasing());

        timelock[selector] = newDuration;
        emit IncreaseTimelock(selector, newDuration);
    }

    function decreaseTimelock(bytes4 selector, uint256 newDuration) external {
        timelocked();
        require(selector != IMidnightAdapterBase.decreaseTimelock.selector, AutomaticallyTimelocked());
        require(newDuration <= timelock[selector], TimelockNotDecreasing());

        timelock[selector] = newDuration;
        emit DecreaseTimelock(selector, newDuration);
    }

    /// @dev This function requires great caution because it will irreversibly disable submit for a selector.
    /// @dev Existing pending operations submitted before abdicating can not be executed at the initial executableAt.
    function abdicate(bytes4 selector) external {
        timelocked();
        abdicated[selector] = true;
        emit Abdicate(selector);
    }

    /* CURATOR FUNCTIONS */

    function increaseMaxTtm(uint256 newMaxTtm) external {
        timelocked();
        require(newMaxTtm >= maxTtm, MaxTtmTooLow());
        maxTtm = newMaxTtm.toUint32();
        emit IncreaseMaxTtm(newMaxTtm);
    }

    function decreaseMaxTtm(uint256 newMaxTtm) external {
        require(
            msg.sender == IVaultV2(parentVault).curator() || IVaultV2(parentVault).isSentinel(msg.sender),
            NotAuthorized()
        );
        require(newMaxTtm <= maxTtm, MaxTtmTooHigh());
        // forge-lint: disable-next-item(unsafe-typecast) safe because newMaxTtm <= maxTtm < 2**32.
        maxTtm = uint32(newMaxTtm);
        emit DecreaseMaxTtm(msg.sender, newMaxTtm);
    }

    /// @dev Buys are prevented as soon as setForceSellable is submitted, until it is revoked or unsetForceSellable is called.
    function setForceSellable(bytes32 marketId) external {
        timelocked();
        marketData[marketId].forceSellable = true;
        emit SetForceSellable(marketId);
    }

    function unsetForceSellable(bytes32 marketId) external {
        require(
            msg.sender == IVaultV2(parentVault).curator() || IVaultV2(parentVault).isSentinel(msg.sender),
            NotAuthorized()
        );
        marketData[marketId].forceSellable = false;
        emit UnsetForceSellable(marketId);
    }

    function setSkimRecipient(address newSkimRecipient) external {
        timelocked();
        skimRecipient = newSkimRecipient;
        emit SetSkimRecipient(newSkimRecipient);
    }

    function setMinNetRate(uint256 newMinNetRate) external {
        require(msg.sender == IVaultV2(parentVault).curator(), NotAuthorized());
        minNetRate = newMinNetRate.toUint64();
        emit SetMinNetRate(newMinNetRate);
    }

    function setNoSalesWithShortfall(bool newNoSalesWithShortfall) external {
        require(msg.sender == IVaultV2(parentVault).curator(), NotAuthorized());
        noSalesWithShortfall = newNoSalesWithShortfall;
        emit SetNoSalesWithShortfall(newNoSalesWithShortfall);
    }

    function setNoSalesBelowFaceValue(bool newNoSalesBelowFaceValue) external {
        require(msg.sender == IVaultV2(parentVault).curator(), NotAuthorized());
        noSalesBelowFaceValue = newNoSalesBelowFaceValue;
        emit SetNoSalesBelowFaceValue(newNoSalesBelowFaceValue);
    }

    /* ALLOCATOR FUNCTIONS */

    function take(Offer memory offer, bytes memory ratifierData, uint256 units, bytes memory takerCallbackData)
        external
    {
        require(IVaultV2(parentVault).isAllocator(msg.sender), NotAuthorized());
        require(offer.market.loanToken == asset, LoanAssetMismatch());
        require(!IMidnight(midnight).liquidationLocked(IdLib.toId(offer.market), address(this)), SellInProgress());
        IMidnight(midnight)
            .take(
                offer,
                ratifierData,
                units,
                address(this),
                offer.buy ? address(this) : address(0),
                address(this),
                takerCallbackData
            );
    }

    /// @dev Setting type(uint128).max cancels all offers of the adapter in the group.
    function setConsumed(bytes32 group, uint128 amount) external {
        require(
            IVaultV2(parentVault).isAllocator(msg.sender) || IVaultV2(parentVault).isSentinel(msg.sender),
            NotAuthorized()
        );
        IMidnight(midnight).setConsumed(group, amount, address(this));
        emit SetConsumed(msg.sender, group, amount);
    }

    function setIsSubRatifier(address subRatifier, bool newIsSubRatifier) external {
        require(
            IVaultV2(parentVault).isAllocator(msg.sender)
                || (!newIsSubRatifier && IVaultV2(parentVault).isSentinel(msg.sender)),
            NotAuthorized()
        );
        isSubRatifier[subRatifier] = newIsSubRatifier;
        emit SetIsSubRatifier(msg.sender, subRatifier, newIsSubRatifier);
    }

    /* OPERATIONS */

    function withdrawToVault(Market memory market, uint256 withdrawnAssets) public {
        bytes32 marketId = IdLib.toId(market);
        require(!IMidnight(midnight).liquidationLocked(marketId, address(this)), SellInProgress());
        // forge-lint: disable-next-item(reentrancy-no-eth) withdraw does not reenter.
        IMidnight(midnight).withdraw(market, withdrawnAssets, address(this), address(this));

        uint128 newNetCredit = currentNetCredit(marketId);
        uint256 oldNetCredit = marketData[marketId].netCredit;
        marketData[marketId].netCredit = newNetCredit;
        marketData[marketId].lossFactor = IMidnight(midnight).lossFactor(marketId);
        if (newNetCredit == 0 && oldNetCredit > 0) removeMarket(marketId);
        // forge-lint: disable-next-item(reentrancy-no-eth, unsafe-typecast) deallocate does not call withdrawToVault; both net credit values fit in uint128.
        IVaultV2(parentVault)
            .deallocate(
                address(this),
                abi.encode(ids(market), int256(uint256(newNetCredit)) - int256(oldNetCredit)),
                withdrawnAssets
            );
        emit WithdrawToVault(marketId, withdrawnAssets, newNetCredit);
    }

    /// @dev Skims the adapter's balance of `token` and sends it to `skimRecipient`.
    /// @dev This is useful to handle rewards that the adapter has earned.
    function skim(address token) external {
        require(msg.sender == skimRecipient, NotAuthorized());
        uint256 balance = IERC20(token).balanceOf(address(this));
        SafeERC20Lib.safeTransfer(token, skimRecipient, balance);
        emit Skim(token, balance);
    }

    /* VAULT INTERFACE */

    /// @dev Called by this adapter from a buy callback to update the vault's allocations.
    /// @dev Returns the bought market's ids and the change in the adapter's net credit in this market.
    function allocate(bytes memory data, uint256, bytes4, address caller)
        external
        view
        returns (bytes32[] memory, int256)
    {
        require(msg.sender == parentVault, NotAuthorized());
        require(caller == address(this), SelfAllocationOnly());
        returnExactBytes(data);
    }

    /// @dev Called by this adapter from a sell callback or a withdraw.
    /// @dev Called by anyone through forceDeallocate. The adapter sells to the given buy offer, with the caller as receiver, and pulls the full credit value from the caller.
    /// @dev Returns the market's ids and the change in the adapter's net credit in this market.
    function deallocate(bytes memory data, uint256 assets, bytes4 messageSig, address caller)
        external
        returns (bytes32[] memory, int256)
    {
        require(msg.sender == parentVault, NotAuthorized());
        SafeERC20Lib.forceApproveMax(asset, parentVault);
        if (messageSig == IVaultV2.forceDeallocate.selector) {
            (Offer memory offer, bytes memory ratifierData) = abi.decode(data, (Offer, bytes));
            require(offer.buy && offer.market.loanToken == asset, IncorrectOffer());
            bytes32 marketId = IdLib.toId(offer.market);
            require(!IMidnight(midnight).liquidationLocked(marketId, address(this)), SellInProgress());
            IVaultV2(parentVault).accrueInterest();

            // Skip onSell since we are already in a deallocate call.
            // forge-lint: disable-next-item(reentrancy-no-eth) the buyer's callback cannot touch this locked market.
            IMidnight(midnight).take(offer, ratifierData, assets, address(this), caller, address(0), hex"");
            SafeERC20Lib.safeTransferFrom(asset, caller, address(this), assets);

            uint128 newNetCredit = currentNetCredit(marketId);
            uint256 oldNetCredit = marketData[marketId].netCredit;
            marketData[marketId].netCredit = newNetCredit;
            marketData[marketId].lossFactor = IMidnight(midnight).lossFactor(marketId);
            if (newNetCredit == 0 && oldNetCredit > 0) removeMarket(marketId);
            emit ForceDeallocate(marketId, assets, newNetCredit);
            // forge-lint: disable-next-item(unsafe-typecast) both net credit values fit in uint128.
            return (ids(offer.market), int256(uint256(newNetCredit)) - int256(oldNetCredit));
        } else {
            require(caller == address(this), SelfAllocationOnly());
            returnExactBytes(data);
        }
    }

    /* MIDNIGHT CALLBACKS */

    /// @dev Returns the result of the sub-ratifier selected in data.
    function isRatified(Offer memory offer, bytes memory data, address taker) external view returns (bytes32) {
        require(!IMidnight(midnight).liquidationLocked(IdLib.toId(offer.market), address(this)), SellInProgress());
        // Gates, RCF threshold, collaterals and durations will be checked in onBuy.
        require(offer.market.midnight == midnight, NotMidnight());
        require(offer.market.loanToken == asset, LoanAssetMismatch());
        require(offer.maker == address(this), IncorrectMaker());
        require(offer.callback == address(this), IncorrectCallbackAddress());
        // For buy offers, Midnight enforces receiverIfMakerIsSeller == address(0).
        require(offer.buy || offer.receiverIfMakerIsSeller == address(this), IncorrectReceiver());

        (address subRatifier, bytes memory subRatifierData) = abi.decode(data, (address, bytes));
        require(isSubRatifier[subRatifier], SubRatifierFailed());
        return IRatifier(subRatifier).isRatified(offer, subRatifierData, taker);
    }

    /// @dev Between recording the purchase and vault.allocate's transfer, realAssets() includes the purchase but the vault has not paid yet.
    /// @dev Can revert on extremely high rates.
    function onBuy(
        bytes32 marketId,
        Market memory market,
        uint256 paidAssets,
        uint256 boughtCredit,
        uint256 buyPendingFeeIncrease,
        address buyer,
        bytes memory callbackData
    ) external returns (bytes32) {
        require(msg.sender == midnight, NotMidnight());
        require(buyer == address(this), NotSelf());
        require(block.timestamp < market.maturity, BuyPostMaturity());
        uint256 ttm = market.maturity - block.timestamp;
        require(ttm <= maxTtm, BuyTtmTooHigh());
        uint256 boughtNetCredit = boughtCredit - buyPendingFeeIncrease;
        require(boughtNetCredit >= paidAssets, BuyAtLoss());
        uint128 newNetCredit = currentNetCredit(marketId);
        (overriddenMarketId, overriddenMarketNetCredit) = (marketId, newNetCredit - boughtNetCredit);
        // forge-lint: disable-next-item(reentrancy-no-eth) accrueInterest only calls view functions of adapters.
        IVaultV2(parentVault).accrueInterest();
        (overriddenMarketId, overriddenMarketNetCredit) = (0, 0);

        MarketData storage _marketData = marketData[marketId];
        require(
            !_marketData.forceSellable
                && executableAt[abi.encodeCall(IMidnightAdapterBase.setForceSellable, (marketId))] == 0,
            UnauthorizedBuy()
        );
        if (newNetCredit > 0) {
            uint256 amortizedValue =
                (newNetCredit - boughtNetCredit).mulDivUp(WAD, WAD + _marketData.netRate * ttm) + paidAssets;
            _marketData.netRate = (newNetCredit - amortizedValue).mulDivDown(WAD, amortizedValue * ttm).toUint64();
            require(_marketData.netRate >= minNetRate, NetRateTooLow());
        }

        uint256 oldNetCredit = _marketData.netCredit;
        _marketData.netCredit = newNetCredit;
        _marketData.lossFactor = IMidnight(midnight).lossFactor(marketId);
        if (newNetCredit > 0 && oldNetCredit == 0) {
            require(marketIds.length < MAX_MARKETS, TooManyMarkets());
            _marketData.maturity = market.maturity.toUint48();
            // forge-lint: disable-next-item(unsafe-typecast) marketIds.length < MAX_MARKETS.
            _marketData.index = uint8(marketIds.length);
            marketIds.push(marketId);
        } else if (newNetCredit == 0 && oldNetCredit > 0) {
            removeMarket(marketId);
        }
        (address fundingAdapter, bytes memory fundingData) = abi.decode(callbackData, (address, bytes));
        if (fundingAdapter == address(this)) {
            withdrawToVault(abi.decode(fundingData, (Market)), paidAssets);
        } else if (fundingAdapter != address(0)) {
            // forge-lint: disable-next-item(reentrancy-no-eth) the adapter is trusted.
            IVaultV2(parentVault).deallocate(fundingAdapter, fundingData, paidAssets);
        }

        // Only durations up to the bought market's time to maturity can have their allocation increased.
        uint256 affectedDurationCount;
        while (affectedDurationCount < durationsLength && packedDurations.get(affectedDurationCount) <= ttm) {
            affectedDurationCount++;
        }
        uint256[] memory allocations = durationAllocations(affectedDurationCount);
        uint256 totalAssets = IVaultV2(parentVault).firstTotalAssets();
        for (uint256 i; i < affectedDurationCount; i++) {
            bytes32 id = keccak256(abi.encode("this/duration", address(this), packedDurations.get(i)));
            uint256 absoluteCap = IVaultV2(parentVault).absoluteCap(id);
            require(absoluteCap > 0, DurationZeroAbsoluteCap());
            require(allocations[i] <= absoluteCap, DurationAbsoluteCapExceeded());
            uint256 relativeCap = IVaultV2(parentVault).relativeCap(id);
            require(
                relativeCap == WAD || allocations[i] <= totalAssets.mulDivDown(relativeCap, WAD),
                DurationRelativeCapExceeded()
            );
        }

        // forge-lint: disable-next-item(reentrancy-no-eth, unsafe-typecast) reentry is expected; both net credit values fit in uint128.
        IVaultV2(parentVault)
            .allocate(
                address(this), abi.encode(ids(market), int256(uint256(newNetCredit)) - int256(oldNetCredit)), paidAssets
            );

        SafeERC20Lib.forceApproveMax(asset, midnight);
        emit Buy(marketId, paidAssets, boughtNetCredit, _marketData.netCredit, _marketData.netRate);
        return CALLBACK_SUCCESS;
    }

    function onSell(
        bytes32 marketId,
        Market memory market,
        uint256 sellerAssets,
        uint256 soldCredit,
        uint256 sellPendingFeeDecrease,
        address seller,
        address,
        bytes memory callbackData
    ) external returns (bytes32) {
        require(msg.sender == midnight, NotMidnight());
        require(seller == address(this), NotSelf());
        require(callbackData.length == 0, NonEmptyCallbackData());

        uint128 newNetCredit = currentNetCredit(marketId);
        uint256 soldNetCredit = soldCredit - sellPendingFeeDecrease;
        require(!noSalesBelowFaceValue || sellerAssets >= soldNetCredit, SaleBelowFaceValue());
        uint256 ttm = market.maturity.zeroFloorSub(block.timestamp);
        MarketData storage _marketData = marketData[marketId];
        uint256 shortfall = soldNetCredit.mulDivUp(WAD, WAD + _marketData.netRate * ttm).zeroFloorSub(sellerAssets);
        if (shortfall > 0) {
            require(!noSalesWithShortfall, SalesWithShortfallDisabled());
            if (!_marketData.forceSellable) {
                uint256 amortizedValue = newNetCredit.mulDivUp(WAD, WAD + _marketData.netRate * ttm) + shortfall;
                require(amortizedValue <= newNetCredit, ShortfallTooHigh());
                _marketData.netRate = (newNetCredit - amortizedValue).mulDivDown(WAD, amortizedValue * ttm).toUint64();
                require(_marketData.netRate >= minNetRate, NetRateTooLow());
            }
        }

        uint256 oldNetCredit = _marketData.netCredit;
        _marketData.netCredit = newNetCredit;
        _marketData.lossFactor = IMidnight(midnight).lossFactor(marketId);
        if (newNetCredit == 0 && oldNetCredit > 0) removeMarket(marketId);
        // forge-lint: disable-next-item(unsafe-typecast) both net credit values fit in uint128.
        IVaultV2(parentVault)
            .deallocate(
                address(this),
                abi.encode(ids(market), int256(uint256(newNetCredit)) - int256(oldNetCredit)),
                sellerAssets
            );

        emit Sell(marketId, sellerAssets, soldNetCredit, newNetCredit, _marketData.netRate);
        return CALLBACK_SUCCESS;
    }

    /* INTERNAL FUNCTIONS */

    /// @dev Ends the external call, returning data without ABI encoding.
    function returnExactBytes(bytes memory data) internal pure {
        assembly ("memory-safe") {
            return(add(data, 32), mload(data))
        }
    }

    /// @dev Returns the adapter's net credit position in marketId.
    /// @dev It does not change with time, so any market struct with maturity 0 will work.
    function currentNetCredit(bytes32 marketId) internal view returns (uint128) {
        Market memory dummyMarket;
        (uint128 credit, uint128 pendingFee,) =
            IMidnight(midnight).updatePositionView(dummyMarket, marketId, address(this));
        return credit - pendingFee;
    }

    function removeMarket(bytes32 marketId) internal {
        MarketData memory _marketData = marketData[marketId];
        bytes32 lastMarketId = marketIds[marketIds.length - 1];
        marketIds[_marketData.index] = lastMarketId;
        marketData[lastMarketId].index = _marketData.index;
        marketIds.pop();
        delete marketData[marketId];
        marketData[marketId].forceSellable = _marketData.forceSellable;
    }

    /* VIEWS */

    /// @dev Returns the number of markets with a non-zero stored net credit.
    function marketIdsLength() external view returns (uint256) {
        return marketIds.length;
    }

    /// @dev Returns the ids that the vault caps for the market: the adapter, the gates, the RCF threshold, and each collateral token and collateral params.
    function ids(Market memory market) public view returns (bytes32[] memory) {
        bytes32[] memory idsArray = new bytes32[](4 + market.collateralParams.length * 2);

        uint256 j;
        idsArray[j++] = adapterId;
        idsArray[j++] = keccak256(abi.encode("enterGate", market.enterGate));
        idsArray[j++] = keccak256(abi.encode("liquidatorGate", market.liquidatorGate));
        idsArray[j++] = keccak256(abi.encode("rcfThreshold", market.rcfThreshold));
        for (uint256 i = 0; i < market.collateralParams.length; i++) {
            idsArray[j++] = keccak256(abi.encode("collateralToken", market.collateralParams[i].token));
            idsArray[j++] = keccak256(abi.encode("collateralParams", market.collateralParams[i]));
        }

        return idsArray;
    }

    /// @dev Returns the durations that can be capped.
    function durations() external view returns (uint256[] memory) {
        uint256[] memory _durations = new uint256[](durationsLength);
        for (uint256 i = 0; i < durationsLength; i++) {
            _durations[i] = packedDurations.get(i);
        }
        return _durations;
    }

    /// @dev Returns, for the first length durations, the stored net credit of markets with at least that duration left to maturity.
    function durationAllocations(uint256 length) public view returns (uint256[] memory allocations) {
        require(length <= durationsLength, InvalidLength());
        allocations = new uint256[](length);
        if (length == 0) return allocations;
        for (uint256 i; i < marketIds.length; i++) {
            MarketData storage _marketData = marketData[marketIds[i]];
            uint256 ttm = _marketData.maturity.zeroFloorSub(block.timestamp);
            uint256 bucket;
            while (bucket < length && packedDurations.get(bucket) <= ttm) bucket++;
            if (bucket > 0) allocations[bucket - 1] += _marketData.netCredit;
        }
        for (uint256 j = length - 1; j > 0; j--) {
            allocations[j - 1] += allocations[j];
        }
    }

    /// @dev Returns the sum over markets of the net credit discounted at the market's rate until maturity.
    function realAssets() external view returns (uint256) {
        uint256 assets;
        for (uint256 i = 0; i < marketIds.length; i++) {
            bytes32 marketId = marketIds[i];
            MarketData storage _marketData = marketData[marketId];
            uint256 netCredit;
            if (marketId == overriddenMarketId) {
                netCredit = overriddenMarketNetCredit;
            } else if (IMidnight(midnight).lossFactor(marketId) == _marketData.lossFactor) {
                netCredit = _marketData.netCredit;
            } else {
                require(!IMidnight(midnight).liquidationLocked(marketId, address(this)), OtherSellInProgress());
                netCredit = currentNetCredit(marketId);
            }
            assets += netCredit.mulDivDown(
                WAD, WAD + _marketData.netRate * _marketData.maturity.zeroFloorSub(block.timestamp)
            );
        }
        return assets;
    }
}
