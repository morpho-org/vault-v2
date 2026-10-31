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
import {PackedDurationsLib} from "./libraries/PackedDurationsLib.sol";

/// VALUATION
/// @dev Approximates held assets by discounting the net credit of each market at a constant simple net rate until maturity.
/// @dev Rate is rounded down. Interest excluded from the rate is realized immediately.
/// @dev Losses are immediately accounted in realAssets() minus a discount applied to the remaining interest to be earned, in proportion to the relative sizes of the loss and the adapter's position in the market hit by the loss.
/// @dev Markets with a zero loss factor use stored net credit; otherwise realAssets reads it from Midnight.
/// @dev The sum of discounted net credits is floored at the sum of net credits minus maxDiscount (see SELLING).
///
/// ROLES
/// @dev The adapter must have the allocator role in its parent vault to buy.
/// @dev The adapter must have the allocator or sentinel role to withdraw to the vault and to sell (except through forceDeallocate).
/// @dev Sub-ratifiers define which offers are authorized.
/// @dev The sentinel can only remove sub-ratifiers.
///
/// BUYING
/// @dev Buy offers must set callbackData to abi.encode(adapter, data) to select where the liquidity will be deallocated, to abi.encode(address(0), "") to pull the liquidity from the vault's idle funds, or to abi.encode(address(this), abi.encode(market)) to withdraw from a Midnight market on the adapter.
/// @dev For self-funding, data is abi.encode(fundingMarket).
///
/// SELLING
/// @dev A sale has a shortfall when the proceeds are less than the amortized value of the sold net credit.
/// @dev Shortfalls pause reported growth instead of reducing rates. Sales revert if remaining interest is insufficient.
/// @dev The floor is total net credit minus maxDiscount.
/// @dev forceSellable sales leave maxDiscount unchanged and realize losses immediately.
/// @dev Visible bad debt is applied before the shortfall.
/// @dev This includes bad debt realized during the sale (e.g. in the buyer callback), which then overvalues the adapter by at most the shortfall right after the sale, and by zero at the last maturity.
///
/// FORCE DEALLOCATE
/// @dev The caller must be the taker, or be authorized by the taker on Midnight.
/// @dev The taker must hold at least 1 share of the parent vault and can then forceDeallocate as much as the penalty allows.
///
/// ALLOCATOR GUARDRAILS
/// @dev minNetBuyRate, maxNetSellRate, noSalesWithShortfall and minForceSellPrice help the curator set guardrails for allocators.
/// @dev Changing these parameters is not timelocked, because they are not used to provide guarantees to depositors.
/// @dev Sales in forceSellable markets ignore maxNetSellRate and noSalesWithShortfall, and are bounded by minForceSellPrice instead.
///
/// CAPS
/// @dev Midnight positions fill caps with their stored net credit, not their discounted book value.
/// @dev When enabled, relative caps compare this face value with recorded total assets, which use book value for Midnight positions.
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
///
/// MISC
/// @dev MidnightAdapters of the same vault, directly or through nested vaults, might not be able to trade with each other, as the buyer's onBuy accrues interest on the vault mid-sale.
contract MidnightAdapter is IMidnightAdapterStaticTyping {
    using MathLib for uint256;
    using MathLib for uint128;
    using MathLib for uint40;
    using PackedDurationsLib for bytes32;

    /* CONSTANTS */

    /// @dev Fillable with dust takes.
    uint256 public constant MAX_MARKETS = 250;
    uint256 public constant MAX_DURATIONS = 8;

    /* IMMUTABLES */

    address public immutable asset;
    address public immutable parentVault;
    address public immutable midnight;
    bytes32 public immutable adapterId;
    /// @dev Sorted in ascending order.
    bytes32 public immutable packedDurations;
    uint256 public immutable durationsLength;

    /* TRANSIENT STORAGE */

    /// @dev Set to true so forceDeallocate offers are ratified.
    bool public transient forceSelling;

    /// @dev Pre-buy credit used by realAssets during vault accrual.
    bytes32 public transient inProgressBuyMarketId;
    uint256 public transient inProgressBuyNetCredit;

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
    /// @dev Sum of net credits minus the floor on realAssets() set by the last sale.
    uint256 public maxDiscount;

    uint32 public maxTtm;
    /// @dev Minimum net rate implied by a maker or taker buy, relative to the paid assets.
    uint64 public minNetBuyRate;
    /// @dev Maximum rate implied by a maker or taker sale, relative to the face value of the sold net credit.
    /// @dev Superseded by minForceSellPrice for forceSellable markets.
    uint64 public maxNetSellRate;
    /// @dev Superseded by minForceSellPrice for forceSellable markets.
    bool public noSalesWithShortfall;

    /* CONSTRUCTOR */

    constructor(address _parentVault, address _midnight, uint256[] memory _durations) {
        asset = IVaultV2(_parentVault).asset();
        parentVault = _parentVault;
        midnight = _midnight;
        IMidnight(_midnight).setIsAuthorized(address(this), true, address(this));
        adapterId = keccak256(abi.encode("this", address(this)));

        require(_durations.length <= MAX_DURATIONS, TooManyDurations());
        uint256 previousDuration;
        for (uint256 i = 0; i < _durations.length; i++) {
            require(_durations[i] > previousDuration, DurationsNotIncreasing());
            require(_durations[i] <= type(uint32).max, DurationTooHigh());
            previousDuration = _durations[i];
        }
        packedDurations = PackedDurationsLib.pack(_durations);
        durationsLength = _durations.length;
        emit Constructor(_parentVault, _midnight, _durations);
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

    /// @dev This function requires great caution because it will irreversibly disable execution of a selector.
    /// @dev Existing pending operations submitted before abdicating can not be executed either.
    function abdicate(bytes4 selector) external {
        timelocked();
        abdicated[selector] = true;
        emit Abdicate(selector);
    }

    /* TIMELOCKED CURATOR SETTINGS */

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
        maxTtm = newMaxTtm.toUint32();
        emit DecreaseMaxTtm(msg.sender, newMaxTtm);
    }

    /// @dev When submitting setForceSellable, it's recommended to put the cap of at least one of the market's ids (e.g. the caps of the id of a broken collateral) to zero, to avoid allocators buying in the market just before it becomes force sellable.
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

    /* NON-TIMELOCKED CURATOR SETTINGS */

    function setMinNetBuyRate(uint256 newMinNetBuyRate) external {
        require(msg.sender == IVaultV2(parentVault).curator(), NotAuthorized());
        minNetBuyRate = newMinNetBuyRate.toUint64();
        emit SetMinNetBuyRate(newMinNetBuyRate);
    }

    function setNoSalesWithShortfall(bool newNoSalesWithShortfall) external {
        require(msg.sender == IVaultV2(parentVault).curator(), NotAuthorized());
        noSalesWithShortfall = newNoSalesWithShortfall;
        emit SetNoSalesWithShortfall(newNoSalesWithShortfall);
    }

    function setMaxNetSellRate(uint256 newMaxNetSellRate) external {
        require(msg.sender == IVaultV2(parentVault).curator(), NotAuthorized());
        maxNetSellRate = newMaxNetSellRate.toUint64();
        emit SetMaxNetSellRate(newMaxNetSellRate);
    }

    function setMinForceSellPrice(bytes32 marketId, uint256 newMinForceSellPrice) external {
        require(msg.sender == IVaultV2(parentVault).curator(), NotAuthorized());
        marketData[marketId].minForceSellPrice = newMinForceSellPrice;
        emit SetMinForceSellPrice(marketId, newMinForceSellPrice);
    }

    /* ALLOCATOR FUNCTIONS */

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

    function withdrawToVault(Market memory market, uint256 withdrawnAssets) public {
        bytes32 marketId = IdLib.toId(market);
        require(!IMidnight(midnight).liquidationLocked(marketId, address(this)), SellInProgress());
        // forge-lint: disable-next-item(reentrancy-no-eth) withdraw does not reenter.
        IMidnight(midnight).withdraw(market, withdrawnAssets, address(this), address(this));

        uint128 newNetCredit = currentNetCredit(marketId);
        uint256 oldNetCredit = marketData[marketId].netCredit;
        marketData[marketId].netCredit = newNetCredit;
        if (newNetCredit == 0 && oldNetCredit > 0) removeMarket(marketId);
        // forge-lint: disable-next-item(unsafe-typecast) both net credit values fit in uint128.
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
    function allocate(bytes memory data, uint256, bytes4, address sender)
        external
        view
        returns (bytes32[] memory, int256)
    {
        require(msg.sender == parentVault, NotAuthorized());
        require(sender == address(this), SelfAllocationOnly());
        returnExactBytes(data);
    }

    /// @dev Called by this adapter from a sell callback or a withdraw.
    /// @dev Called by anyone through forceDeallocate. The adapter sells credit of the given market to the given taker at face value plus the settlement fee, paid by the sender.
    /// @dev Returns the market's ids and the change in the adapter's net credit in this market.
    function deallocate(bytes memory data, uint256 assets, bytes4 selector, address sender)
        external
        returns (bytes32[] memory, int256)
    {
        require(msg.sender == parentVault, NotAuthorized());
        SafeERC20Lib.forceApproveMax(asset, parentVault);
        if (selector == IVaultV2.forceDeallocate.selector) {
            (Market memory market, address taker) = abi.decode(data, (Market, address));
            require(taker == sender || IMidnight(midnight).isAuthorized(taker, sender), NotAuthorized());
            require(IVaultV2(parentVault).balanceOf(taker) > 0, TakerHasNoShares());
            require(market.loanToken == asset, LoanAssetMismatch());
            bytes32 marketId = IdLib.toId(market);
            require(!IMidnight(midnight).liquidationLocked(marketId, address(this)), SellInProgress());
            Offer memory offer = Offer({
                market: market,
                buy: false,
                maker: address(this),
                start: 0,
                expiry: type(uint256).max,
                tick: 0,
                group: bytes32(0),
                callback: address(0),
                callbackData: hex"",
                receiverIfMakerIsSeller: address(this),
                ratifier: address(this),
                reduceOnly: true,
                maxUnits: 0,
                maxAssets: type(uint128).max,
                continuousFeeCap: type(uint256).max
            });
            uint256 settlementFeeAssets = assets.mulDivUp(
                IMidnight(midnight).settlementFee(marketId, market.maturity.zeroFloorSub(block.timestamp)), WAD
            );
            SafeERC20Lib.safeTransferFrom(asset, sender, address(this), assets + settlementFeeAssets);
            forceSelling = true;
            // Skip onSell since we are already in a deallocate call.
            IMidnight(midnight).take(offer, hex"", assets, taker, address(0), address(0), hex"");
            forceSelling = false;

            uint128 newNetCredit = currentNetCredit(marketId);
            uint256 oldNetCredit = marketData[marketId].netCredit;
            marketData[marketId].netCredit = newNetCredit;
            if (newNetCredit == 0 && oldNetCredit > 0) removeMarket(marketId);
            emit ForceDeallocate(marketId, assets, newNetCredit);
            // forge-lint: disable-next-item(unsafe-typecast) both net credit values fit in uint128.
            return (ids(market), int256(uint256(newNetCredit)) - int256(oldNetCredit));
        } else {
            require(sender == address(this), SelfAllocationOnly());
            returnExactBytes(data);
        }
    }

    /* MIDNIGHT CALLBACKS */

    /// @dev Returns the result of the sub-ratifier selected in ratifierData, except while the adapter takes its own offer through forceDeallocate.
    function isRatified(Offer memory offer, bytes memory ratifierData, address taker) external view returns (bytes32) {
        if (forceSelling) return CALLBACK_SUCCESS;
        require(!IMidnight(midnight).liquidationLocked(IdLib.toId(offer.market), address(this)), SellInProgress());
        // Gates, RCF threshold, collaterals and durations will be checked in onBuy.
        require(offer.market.midnight == midnight, NotMidnight());
        require(offer.market.loanToken == asset, LoanAssetMismatch());
        require(offer.maker == address(this), IncorrectMaker());
        require(offer.callback == address(this), IncorrectCallbackAddress());
        // For buy offers, Midnight enforces receiverIfMakerIsSeller == address(0).
        require(offer.buy || offer.receiverIfMakerIsSeller == address(this), IncorrectReceiver());

        (address subRatifier, bytes memory subRatifierData) = abi.decode(ratifierData, (address, bytes));
        require(isSubRatifier[subRatifier], SubRatifierFailed());
        return IRatifier(subRatifier).isRatified(offer, subRatifierData, taker);
    }

    /// @dev Between recording the purchase and vault.allocate's transfer, realAssets() includes the purchase but the vault has not paid yet.
    /// @dev Can revert on extremely high rates.
    function onBuy(
        bytes32 id,
        Market memory market,
        uint256 buyerAssets,
        uint256 units,
        uint256 pendingFeeIncrease,
        address buyer,
        bytes memory data
    ) external returns (bytes32) {
        require(msg.sender == midnight, NotMidnight());
        require(buyer == address(this), NotSelf());
        require(block.timestamp < market.maturity, BuyPostMaturity());
        uint256 ttm = market.maturity - block.timestamp;
        require(ttm <= maxTtm, BuyTtmTooHigh());
        MarketData storage _marketData = marketData[id];
        require(!_marketData.forceSellable, UnauthorizedBuy());
        uint256 boughtNetCredit = units - pendingFeeIncrease;
        require(boughtNetCredit >= buyerAssets, BuyAtLoss());
        require((boughtNetCredit - buyerAssets) * WAD >= minNetBuyRate * ttm * buyerAssets, NetBuyRateTooLow());

        uint128 newNetCredit = currentNetCredit(id);
        uint256 oldNetCredit = _marketData.netCredit;
        _marketData.netCredit = newNetCredit;
        (inProgressBuyMarketId, inProgressBuyNetCredit) = (id, newNetCredit - boughtNetCredit);
        // forge-lint: disable-next-item(reentrancy-no-eth) accrueInterest only calls view functions of adapters.
        IVaultV2(parentVault).accrueInterest();
        (inProgressBuyMarketId, inProgressBuyNetCredit) = (bytes32(0), 0);

        if (newNetCredit > 0) {
            uint256 amortizedValue =
                (newNetCredit - boughtNetCredit).mulDivUp(WAD, WAD + _marketData.netRate * ttm) + buyerAssets;
            _marketData.netRate = (newNetCredit - amortizedValue).mulDivDown(WAD, amortizedValue * ttm).toUint72();
        }
        maxDiscount += boughtNetCredit - buyerAssets;

        if (newNetCredit > 0 && oldNetCredit == 0) {
            require(marketIds.length < MAX_MARKETS, TooManyMarkets());
            _marketData.maturity = market.maturity.toUint40();
            // forge-lint: disable-next-item(unsafe-typecast) marketIds.length < MAX_MARKETS.
            _marketData.index = uint8(marketIds.length);
            marketIds.push(id);
        } else if (newNetCredit == 0 && oldNetCredit > 0) {
            removeMarket(id);
        }

        (address fundingAdapter, bytes memory fundingData) = abi.decode(data, (address, bytes));
        if (fundingAdapter == address(this)) {
            withdrawToVault(abi.decode(fundingData, (Market)), buyerAssets);
        } else if (fundingAdapter != address(0)) {
            IVaultV2(parentVault).deallocate(fundingAdapter, fundingData, buyerAssets);
        }

        // Only durations up to the bought market's time to maturity can have their allocation increased.
        uint256 affectedDurationCount;
        while (affectedDurationCount < durationsLength && packedDurations.get(affectedDurationCount) <= ttm) {
            affectedDurationCount++;
        }
        uint256[] memory allocations = durationAllocations(affectedDurationCount);
        uint256 totalAssets = IVaultV2(parentVault).firstTotalAssets();
        for (uint256 i; i < affectedDurationCount; i++) {
            bytes32 durationId = keccak256(abi.encode("this/duration", address(this), packedDurations.get(i)));
            uint256 absoluteCap = IVaultV2(parentVault).absoluteCap(durationId);
            require(absoluteCap > 0, DurationZeroAbsoluteCap());
            require(allocations[i] <= absoluteCap, DurationAbsoluteCapExceeded());
            uint256 relativeCap = IVaultV2(parentVault).relativeCap(durationId);
            require(
                relativeCap == WAD || allocations[i] <= totalAssets.mulDivDown(relativeCap, WAD),
                DurationRelativeCapExceeded()
            );
        }

        // forge-lint: disable-next-item(unsafe-typecast) both net credit values fit in uint128.
        IVaultV2(parentVault)
            .allocate(
                address(this),
                abi.encode(ids(market), int256(uint256(newNetCredit)) - int256(oldNetCredit)),
                buyerAssets
            );

        SafeERC20Lib.forceApproveMax(asset, midnight);
        emit Buy(id, buyerAssets, boughtNetCredit, _marketData.netCredit, _marketData.netRate);
        return CALLBACK_SUCCESS;
    }

    function onSell(
        bytes32 id,
        Market memory market,
        uint256 sellerAssets,
        uint256 units,
        uint256 pendingFeeDecrease,
        address seller,
        address,
        bytes memory data
    ) external returns (bytes32) {
        require(msg.sender == midnight, NotMidnight());
        require(seller == address(this), NotSelf());
        require(data.length == 0, NonEmptyCallbackData());

        uint128 newNetCredit = currentNetCredit(id);
        uint256 soldNetCredit = units - pendingFeeDecrease;
        MarketData storage _marketData = marketData[id];
        if (_marketData.forceSellable) {
            require(sellerAssets >= soldNetCredit.mulDivUp(_marketData.minForceSellPrice, WAD), ForceSellPriceTooLow());
        } else {
            uint256 ttm = market.maturity.zeroFloorSub(block.timestamp);
            require(sellerAssets >= soldNetCredit.mulDivUp(WAD, WAD + maxNetSellRate * ttm), NetSellRateTooHigh());
            require(
                !noSalesWithShortfall || sellerAssets >= soldNetCredit.mulDivUp(WAD, WAD + _marketData.netRate * ttm),
                SalesWithShortfallDisabled()
            );
            (, uint256 totalDiscount) = currentPosition(id, newNetCredit + soldNetCredit);
            maxDiscount = MathLib.min(totalDiscount, maxDiscount) + sellerAssets - soldNetCredit;
        }

        uint256 oldNetCredit = _marketData.netCredit;
        _marketData.netCredit = newNetCredit;
        if (newNetCredit == 0 && oldNetCredit > 0) removeMarket(id);
        // forge-lint: disable-next-item(unsafe-typecast) both net credit values fit in uint128.
        IVaultV2(parentVault)
            .deallocate(
                address(this),
                abi.encode(ids(market), int256(uint256(newNetCredit)) - int256(oldNetCredit)),
                sellerAssets
            );

        emit Sell(id, sellerAssets, soldNetCredit, newNetCredit, maxDiscount);
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

    /// @dev Returns marketIds[i] without the bounds check. Assumes i < marketIds.length.
    function marketIdAt(uint256 i) internal view returns (bytes32 marketId) {
        assembly ("memory-safe") {
            mstore(0, marketIds.slot)
            marketId := sload(add(keccak256(0, 32), i))
        }
    }

    /// @dev Returns net credit and uncapped discount, using the supplied credit for overrideMarketId.
    function currentPosition(bytes32 overrideMarketId, uint256 overrideNetCredit)
        internal
        view
        returns (uint256, uint256)
    {
        uint256 totalNetCredit;
        uint256 totalDiscount;
        for (uint256 i = 0; i < marketIds.length; i++) {
            bytes32 marketId = marketIdAt(i);
            MarketData storage _marketData = marketData[marketId];
            uint128 storedNetCredit = _marketData.netCredit;
            uint72 netRate = _marketData.netRate;
            uint40 maturity = _marketData.maturity;
            uint256 netCredit;
            if (marketId == overrideMarketId) {
                netCredit = overrideNetCredit;
            } else if (IMidnight(midnight).lossFactor(marketId) == 0) {
                netCredit = storedNetCredit;
            } else {
                require(!IMidnight(midnight).liquidationLocked(marketId, address(this)), OtherSellInProgress());
                netCredit = currentNetCredit(marketId);
            }
            totalNetCredit += netCredit;
            // Cannot overflow: numerator (uint128 * WAD) and denominator (WAD + uint72 * uint40) are << 2^256.
            // Each iteration adds at most netCredit (uint128) and there are at most MAX_MARKETS additions, so totalDiscount does not overflow either.
            unchecked {
                totalDiscount += netCredit - netCredit * WAD / (WAD + netRate * maturity.zeroFloorSub(block.timestamp));
            }
        }
        return (totalNetCredit, totalDiscount);
    }

    function removeMarket(bytes32 marketId) internal {
        MarketData storage _marketData = marketData[marketId];
        bytes32 lastMarketId = marketIds[marketIds.length - 1];
        marketIds[_marketData.index] = lastMarketId;
        marketData[lastMarketId].index = _marketData.index;
        marketIds.pop();
        _marketData.netRate = 0;
        _marketData.maturity = 0;
        _marketData.index = 0;
    }

    /* VIEWS */

    /// @dev Returns the number of markets with a non-zero stored net credit.
    function marketIdsLength() external view returns (uint256) {
        return marketIds.length;
    }

    /// @dev Returns the ids that the vault caps for the market: the adapter, the enter gate, the liquidator gate (if non-zero), the RCF threshold, and each collateral token and collateral params.
    function ids(Market memory market) public view returns (bytes32[] memory) {
        bytes32[] memory idsArray =
            new bytes32[](3 + (market.liquidatorGate != address(0) ? 1 : 0) + market.collateralParams.length * 2);

        uint256 j;
        idsArray[j++] = adapterId;
        idsArray[j++] = keccak256(abi.encode("enterGate", market.enterGate));
        if (market.liquidatorGate != address(0)) {
            idsArray[j++] = keccak256(abi.encode("liquidatorGate", market.liquidatorGate));
        }
        idsArray[j++] = keccak256(abi.encode("rcfThreshold", market.rcfThreshold));
        for (uint256 i = 0; i < market.collateralParams.length; i++) {
            idsArray[j++] = keccak256(abi.encode("collateralToken", market.collateralParams[i].token));
            idsArray[j++] = keccak256(abi.encode("collateralParams", market.collateralParams[i]));
        }

        return idsArray;
    }

    /// @dev Returns the durations that can be capped.
    function durations() external view returns (uint256[] memory) {
        return packedDurations.unpack(durationsLength);
    }

    /// @dev Returns, for the first length durations, the stored net credit of markets with at least that duration left to maturity.
    function durationAllocations(uint256 length) public view returns (uint256[] memory) {
        require(length <= durationsLength, InvalidLength());
        uint256[] memory allocations = new uint256[](length);
        if (length == 0) return allocations;
        for (uint256 i; i < marketIds.length; i++) {
            MarketData storage _marketData = marketData[marketIds[i]];
            uint256 ttm = _marketData.maturity.zeroFloorSub(block.timestamp);
            uint256 bucket;
            for (; bucket < length; bucket++) {
                if (packedDurations.get(bucket) > ttm) break;
            }
            if (bucket > 0) allocations[bucket - 1] += _marketData.netCredit;
        }
        for (uint256 j = length - 1; j > 0; j--) {
            allocations[j - 1] += allocations[j];
        }
        return allocations;
    }

    /// @dev Returns the sum over markets of the net credit discounted at the market's rate until maturity, floored at the sum of net credits minus maxDiscount.
    function realAssets() external view returns (uint256) {
        (uint256 totalNetCredit, uint256 totalDiscount) = currentPosition(inProgressBuyMarketId, inProgressBuyNetCredit);
        return totalNetCredit - MathLib.min(totalDiscount, maxDiscount);
    }
}
