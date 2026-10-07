// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Morpho Association
pragma solidity 0.8.34;

import {IMidnight, Offer, Market} from "lib/midnight/src/interfaces/IMidnight.sol";
import {IRatifier} from "lib/midnight/src/interfaces/IRatifier.sol";
import {IdLib} from "lib/midnight/src/libraries/IdLib.sol";
import {CALLBACK_SUCCESS} from "lib/midnight/src/libraries/ConstantsLib.sol";
import {IERC20} from "../interfaces/IERC20.sol";
import {SafeERC20Lib} from "../libraries/SafeERC20Lib.sol";
import {MathLib} from "../libraries/MathLib.sol";
import {WAD} from "../libraries/ConstantsLib.sol";
import {IVaultV2} from "../interfaces/IVaultV2.sol";
import {IMidnightAdapterBase, IMidnightAdapterStaticTyping, MarketData} from "./interfaces/IMidnightAdapter.sol";
import {DurationsLib} from "./libraries/DurationsLib.sol";

/// @dev Approximates held assets by linearly accounting for interest per market.
/// @dev Growth is rounded down. Interest excluded from growth is realized immediately.
/// @dev Losses are immediately accounted in realAssets() minus a discount applied to the remaining interest to be earned, in proportion to the relative sizes of the loss and the adapter's position in the market hit by the loss.
/// @dev The adapter must have the allocator role in its parent vault to buy.
/// @dev The adapter must have the allocator or sentinel role to withdraw to the vault and to sell (except through forceDeallocate).
/// @dev Buy offers must set callbackData to abi.encode(adapter, data) to select where the liquidity will be deallocated, or to "" to take the liquidity in the vault's idle funds.
/// @dev For self-funding, data is abi.encode(fundingMarket).
/// @dev Before adding the adapter to the vault, its timelocks must be properly set.
/// @dev A shortfall is the negative delta if any between the amortized value of sold credit and the actual sales proceeds.
/// @dev The adapter's allocation cap bounds exposure.
/// @dev The shortfall allowance refill rounds down, and anyone can trigger a refresh (e.g. with a no-op withdrawToVault). Refreshing every block stops the allowance from growing when allowanceCap.mulDivDown(blockTime, shortfallRefillPeriod) rounds to 0. This can only reduce adapter max sell losses.
///
/// TIMELOCKS
/// @dev The system is the same as the one used in VaultV2. Dev comments in VaultV2.sol on timelocks also apply here.
contract MidnightAdapter is IMidnightAdapterStaticTyping {
    using MathLib for uint256;
    using MathLib for uint136;
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
    /// @dev Durations that can be used to cap the time to maturity.
    /// @dev Sorted in ascending order.
    /// @dev The caps of a duration are the vault's caps of the id keccak256(abi.encode("duration", adapter, duration)).
    /// @dev The vault's allocation of this id stays zero: the adapter enforces these caps itself on buys.
    bytes32 public immutable packedDurations;
    uint256 public immutable durationsLength;

    /* TRANSIENT STORAGE */

    bytes32 transient overridenMarketId;
    uint256 transient overridenMarketNetCredit;

    /* TIMELOCKS STORAGE */

    mapping(bytes4 selector => uint256) public timelock;
    mapping(bytes4 selector => bool) public abdicated;
    mapping(bytes data => uint256) public executableAt;

    /* ADAPTER STORAGE */

    address public skimRecipient;
    mapping(address subRatifier => bool) public isSubRatifier;
    /// @dev Zero may still prevent the adapter from taking buy offers priced at 1 on a market with a nonzero settlement fee.
    /// @dev Enforced on maker and taker sales before maturity only.
    mapping(bytes32 collateralParamsHash => uint256) public maxSellRate;

    bytes32[] public marketIds;
    /// @dev Net credit last reported to the vault's caps.
    mapping(bytes32 marketId => MarketData) public marketData;

    /// @dev Refill period in seconds. Zero restores the full allowance on every update.
    uint40 public shortfallRefillPeriod;
    uint32 public maxTtm;
    uint48 public shortfallUpdatedAt;
    uint136 public totalNetCredit;

    uint64 public maxShortfallRatio;
    /// @dev Minimum net simple interest rate per second, WAD-scaled, enforced on maker and taker buys before maturity.
    uint64 public minBuyRate;
    uint128 public shortfallAllowance;

    /* CONSTRUCTOR */

    constructor(address _parentVault, address _midnight, uint256[] memory _durations) {
        asset = IVaultV2(_parentVault).asset();
        parentVault = _parentVault;
        midnight = _midnight;
        IMidnight(_midnight).setIsAuthorized(address(this), true, address(this));
        SafeERC20Lib.safeApprove(asset, _midnight, type(uint256).max);
        SafeERC20Lib.safeApprove(asset, _parentVault, type(uint256).max);
        adapterId = keccak256(abi.encode("this", address(this)));

        packedDurations = DurationsLib.pack(_durations);
        durationsLength = _durations.length;
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

    /// @dev This function requires great caution because it will irreversibly disable submit for a selector.
    /// @dev Existing pending operations submitted before abdicating can not be executed at the initial executableAt.
    function abdicate(bytes4 selector) external {
        timelocked();
        abdicated[selector] = true;
        emit Abdicate(selector);
    }

    /* CURATOR FUNCTIONS */

    function setMaxTtm(uint256 newMaxTtm) external {
        timelocked();
        maxTtm = newMaxTtm.toUint32();
        emit SetMaxTtm(newMaxTtm);
    }

    function setSkimRecipient(address newSkimRecipient) external {
        timelocked();
        skimRecipient = newSkimRecipient;
        emit SetSkimRecipient(newSkimRecipient);
    }

    function setMaxShortfallRatio(uint256 newMaxShortfallRatio) external {
        timelocked();
        require(newMaxShortfallRatio <= WAD, MaxShortfallRatioTooHigh());
        updateShortfallAllowance();
        maxShortfallRatio = newMaxShortfallRatio.toUint64();
        emit SetMaxShortfallRatio(newMaxShortfallRatio, shortfallAllowance);
    }

    function setShortfallRefillPeriod(uint256 newShortfallRefillPeriod) external {
        timelocked();
        updateShortfallAllowance();
        shortfallRefillPeriod = newShortfallRefillPeriod.toUint40();
        emit SetShortfallRefillPeriod(newShortfallRefillPeriod, shortfallAllowance);
    }

    /// @dev Help prevent operational errors when buying.
    function setMinBuyRate(uint256 newMinBuyRate) external {
        require(msg.sender == IVaultV2(parentVault).curator(), NotAuthorized());
        minBuyRate = newMinBuyRate.toUint64();
        emit SetMinBuyRate(newMinBuyRate);
    }

    /// @dev Help prevent operational errors when selling.
    function setMaxSellRate(bytes32 collateralParamsHash, uint256 newMaxSellRate) external {
        require(msg.sender == IVaultV2(parentVault).curator(), NotAuthorized());
        maxSellRate[collateralParamsHash] = newMaxSellRate;
        emit SetMaxSellRate(msg.sender, collateralParamsHash, newMaxSellRate);
    }

    /* ALLOCATOR FUNCTIONS */

    function take(Offer memory offer, bytes memory ratifierData, uint256 units) external {
        require(IVaultV2(parentVault).isAllocator(msg.sender), NotAuthorized());
        require(offer.market.loanToken == asset, LoanAssetMismatch());
        require(!IMidnight(midnight).liquidationLocked(IdLib.toId(offer.market), address(this)), SellInProgress());
        IMidnight(midnight)
            .take(
                offer, ratifierData, units, address(this), offer.buy ? address(this) : address(0), address(this), hex""
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

    /// @dev Sub-ratifiers define how allocator offers are authorized.
    /// @dev The sentinel can only remove sub-ratifiers.
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
        updateShortfallAllowance();

        // forge-lint: disable-next-item(reentrancy-no-eth) withdraw does not reenter.
        IMidnight(midnight).withdraw(market, withdrawnAssets, address(this), address(this));

        uint128 newNetCredit = currentNetCredit(marketId);
        uint256 oldNetCredit = marketData[marketId].netCredit;
        marketData[marketId].netCredit = newNetCredit;
        if (newNetCredit == 0 && oldNetCredit > 0) removeMarket(marketId);
        // forge-lint: disable-next-item(unsafe-typecast) at most MAX_MARKETS + 1 uint128 values are summed.
        totalNetCredit = uint136(totalNetCredit + newNetCredit - oldNetCredit);

        // forge-lint: disable-next-item(reentrancy-no-eth, unsafe-typecast) deallocate does not call withdrawToVault; both net credit values fit in uint128.
        IVaultV2(parentVault)
            .deallocate(
                address(this),
                abi.encode(ids(market), int256(uint256(newNetCredit)) - int256(oldNetCredit)),
                withdrawnAssets
            );
        emit WithdrawToVault(marketId, withdrawnAssets, newNetCredit, shortfallAllowance);
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
    /// @dev Called by anyone through forceDeallocate. The adapter sells to the given buy offer, with the caller as receiver and pulls the full credit value from the caller.
    function deallocate(bytes memory data, uint256 assets, bytes4 messageSig, address caller)
        external
        returns (bytes32[] memory, int256)
    {
        require(msg.sender == parentVault, NotAuthorized());
        if (messageSig == IVaultV2.forceDeallocate.selector) {
            (Offer memory offer, bytes memory ratifierData) = abi.decode(data, (Offer, bytes));
            require(offer.buy && offer.market.loanToken == asset, IncorrectOffer());
            bytes32 marketId = IdLib.toId(offer.market);
            require(!IMidnight(midnight).liquidationLocked(marketId, address(this)), SellInProgress());
            IVaultV2(parentVault).accrueInterest();
            updateShortfallAllowance();

            // Skip onSell since we are already in a deallocate call.
            // forge-lint: disable-next-item(reentrancy-no-eth) the buyer's callback cannot touch this locked market.
            IMidnight(midnight).take(offer, ratifierData, assets, address(this), caller, address(0), hex"");
            SafeERC20Lib.safeTransferFrom(asset, caller, address(this), assets);

            uint128 newNetCredit = currentNetCredit(marketId);
            uint256 oldNetCredit = marketData[marketId].netCredit;
            marketData[marketId].netCredit = newNetCredit;
            if (newNetCredit == 0 && oldNetCredit > 0) removeMarket(marketId);
            // forge-lint: disable-next-item(unsafe-typecast) at most MAX_MARKETS + 1 uint128 values are summed.
            totalNetCredit = uint136(totalNetCredit + newNetCredit - oldNetCredit);

            emit ForceDeallocate(marketId, assets, newNetCredit, shortfallAllowance);
            // forge-lint: disable-next-item(unsafe-typecast) both net credit values fit in uint128.
            return (ids(offer.market), int256(uint256(newNetCredit)) - int256(oldNetCredit));
        } else {
            require(caller == address(this), SelfAllocationOnly());
            returnExactBytes(data);
        }
    }

    /* MIDNIGHT CALLBACKS */

    function isRatified(Offer memory offer, bytes memory data, address taker) external view returns (bytes32) {
        require(!IMidnight(midnight).liquidationLocked(IdLib.toId(offer.market), address(this)), SellInProgress());
        // Gates, RCF threshold, collaterals and durations will be checked in onBuy.
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
        require(block.timestamp <= market.maturity, BuyPostMaturity());
        require(market.maturity - block.timestamp <= maxTtm, BuyTtmTooHigh());
        uint256 boughtNetCredit = boughtCredit - buyPendingFeeIncrease;
        require(boughtNetCredit >= paidAssets, BuyAtLoss());
        updateShortfallAllowance();

        // Cache corrected net credit before call to allocate
        uint128 newNetCredit = currentNetCredit(marketId);
        (overridenMarketId, overridenMarketNetCredit) = (marketId, newNetCredit - boughtNetCredit);
        // forge-lint: disable-next-item(reentrancy-no-eth) accrueInterest only calls view functions of adapters.
        IVaultV2(parentVault).accrueInterest();
        (overridenMarketId, overridenMarketNetCredit) = (0, 0);

        MarketData storage _marketData = marketData[marketId];
        if (block.timestamp < market.maturity && boughtNetCredit > 0) {
            uint256 addedAssetsWadPerSecond =
                (boughtNetCredit - paidAssets).mulDivDown(WAD, market.maturity - block.timestamp);
            require(addedAssetsWadPerSecond >= minBuyRate * paidAssets, BuyRateTooLow());

            uint256 oldAssetsWadPerSecond = (newNetCredit - boughtNetCredit) * _marketData.growth;
            // forge-lint: disable-next-item(unsafe-typecast) growth <= WAD < 2**64.
            _marketData.growth = uint64((oldAssetsWadPerSecond + addedAssetsWadPerSecond) / newNetCredit);
        }

        uint256 oldNetCredit = _marketData.netCredit;
        _marketData.netCredit = newNetCredit;
        if (newNetCredit > 0 && oldNetCredit == 0) {
            require(marketIds.length < MAX_MARKETS, TooManyMarkets());
            _marketData.maturity = market.maturity.toUint48();
            // forge-lint: disable-next-item(unsafe-typecast) marketIds.length < MAX_MARKETS.
            _marketData.index = uint8(marketIds.length);
            marketIds.push(marketId);
        } else if (newNetCredit == 0 && oldNetCredit > 0) {
            removeMarket(marketId);
        }
        // forge-lint: disable-next-item(unsafe-typecast) at most MAX_MARKETS + 1 uint128 values are summed.
        totalNetCredit = uint136(totalNetCredit + newNetCredit - oldNetCredit);

        uint256 idleAssets = IERC20(asset).balanceOf(parentVault);
        if (callbackData.length > 0 && paidAssets > idleAssets) {
            (address fundingAdapter, bytes memory fundingData) = abi.decode(callbackData, (address, bytes));
            if (fundingAdapter == address(this)) {
                withdrawToVault(abi.decode(fundingData, (Market)), paidAssets - idleAssets);
            } else {
                // forge-lint: disable-next-item(reentrancy-no-eth) the adapter is trusted.
                IVaultV2(parentVault).deallocate(fundingAdapter, fundingData, paidAssets - idleAssets);
            }
        }

        // Only durations up to the bought market's time to maturity can have their allocation increased.
        uint256 ttm = market.maturity - block.timestamp;
        uint256 affectedDurationCount;
        while (affectedDurationCount < durationsLength && packedDurations.get(affectedDurationCount) <= ttm) {
            affectedDurationCount++;
        }
        uint256[] memory allocations = durationAllocations(affectedDurationCount);
        uint256 totalAssets = IVaultV2(parentVault).firstTotalAssets();
        for (uint256 i; i < affectedDurationCount; i++) {
            bytes32 id = keccak256(abi.encode("duration", address(this), packedDurations.get(i)));
            require(allocations[i] <= IVaultV2(parentVault).absoluteCap(id), DurationAbsoluteCapExceeded());
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

        emit Buy(marketId, paidAssets, boughtNetCredit, _marketData.netCredit, shortfallAllowance);
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
        bytes memory
    ) external returns (bytes32) {
        require(msg.sender == midnight, NotMidnight());
        require(seller == address(this), NotSelf());
        updateShortfallAllowance();

        uint128 newNetCredit = currentNetCredit(marketId);
        uint256 soldNetCredit = soldCredit - sellPendingFeeDecrease;
        if (block.timestamp < market.maturity && soldNetCredit > sellerAssets) {
            require(
                (soldNetCredit - sellerAssets).mulDivUp(WAD, (market.maturity - block.timestamp) * sellerAssets)
                    <= maxSellRate[keccak256(abi.encode(market.collateralParams))],
                SellRateTooHigh()
            );
        }

        MarketData storage _marketData = marketData[marketId];
        uint256 discountFactor = WAD - _marketData.growth * market.maturity.zeroFloorSub(block.timestamp);
        uint256 assetsBefore = (newNetCredit + soldNetCredit).mulDivDown(discountFactor, WAD);
        uint256 assetsAfter = newNetCredit.mulDivDown(discountFactor, WAD);
        uint256 saleShortfall = (assetsBefore - assetsAfter).zeroFloorSub(sellerAssets);
        if (saleShortfall > 0) {
            require(saleShortfall <= shortfallAllowance, MaxShortfallExceeded());
            shortfallAllowance -= saleShortfall.toUint128();
        }

        uint256 oldNetCredit = _marketData.netCredit;
        _marketData.netCredit = newNetCredit;
        if (newNetCredit == 0 && oldNetCredit > 0) removeMarket(marketId);
        // forge-lint: disable-next-item(unsafe-typecast) at most MAX_MARKETS + 1 uint128 values are summed.
        totalNetCredit = uint136(totalNetCredit + newNetCredit - oldNetCredit);

        // forge-lint: disable-next-item(unsafe-typecast) both net credit values fit in uint128.
        IVaultV2(parentVault)
            .deallocate(
                address(this),
                abi.encode(ids(market), int256(uint256(newNetCredit)) - int256(oldNetCredit)),
                sellerAssets
            );

        emit Sell(marketId, sellerAssets, newNetCredit, saleShortfall, shortfallAllowance);
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

    /// @dev Uses stored totalNetCredit; newly recognized losses affect the next update.
    /// @dev A zero refill period restores the full allowance on every update.
    function updateShortfallAllowance() internal {
        uint256 allowanceCap = MathLib.min(totalNetCredit.mulDivDown(maxShortfallRatio, WAD), type(uint128).max);
        shortfallAllowance = shortfallRefillPeriod == 0
            ? allowanceCap.toUint128()
            : MathLib.min(
                    allowanceCap,
                    shortfallAllowance
                        + allowanceCap.mulDivDown(block.timestamp - shortfallUpdatedAt, shortfallRefillPeriod)
                )
                .toUint128();
        shortfallUpdatedAt = block.timestamp.toUint48();
    }

    /// @dev Removes the market from marketIds and clears its stored data.
    function removeMarket(bytes32 marketId) internal {
        MarketData storage _marketData = marketData[marketId];
        bytes32 lastMarketId = marketIds[marketIds.length - 1];
        marketIds[_marketData.index] = lastMarketId;
        marketData[lastMarketId].index = _marketData.index;
        marketIds.pop();
        delete marketData[marketId];
    }

    /* VIEWS */

    function marketIdsLength() external view returns (uint256) {
        return marketIds.length;
    }

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
    /// @dev A position counts toward every duration <= its current remaining time to maturity.
    function durations() public view returns (uint256[] memory) {
        uint256[] memory _durations = new uint256[](durationsLength);
        for (uint256 i = 0; i < durationsLength; i++) {
            _durations[i] = packedDurations.get(i);
        }
        return _durations;
    }

    /// @dev Returns, for the first length durations, the stored net credit of markets with at least that duration left to maturity.
    /// @dev Stored net credit is an upper bound of the exposure at each check.
    function durationAllocations(uint256 length) public view returns (uint256[] memory allocations) {
        require(length <= durationsLength, InvalidLength());
        allocations = new uint256[](length);
        if (length == 0) return allocations;
        for (uint256 i; i < marketIds.length; i++) {
            MarketData storage _marketData = marketData[marketIds[i]];
            uint256 ttm = uint256(_marketData.maturity).zeroFloorSub(block.timestamp);
            uint256 bucket;
            while (bucket < length && packedDurations.get(bucket) <= ttm) bucket++;
            if (bucket > 0) allocations[bucket - 1] += _marketData.netCredit;
        }
        for (uint256 j = length - 1; j > 0; j--) {
            allocations[j - 1] += allocations[j];
        }
    }

    function realAssets() external view returns (uint256) {
        uint256 assets;
        uint256 length = marketIds.length;
        for (uint256 i = 0; i < length; i++) {
            bytes32 marketId = marketIds[i];
            MarketData storage _marketData = marketData[marketId];
            uint256 newNetCredit;
            if (marketId == overridenMarketId) {
                newNetCredit = overridenMarketNetCredit;
            } else {
                require(!IMidnight(midnight).liquidationLocked(marketId, address(this)), OtherSellInProgress());
                newNetCredit = currentNetCredit(marketId);
            }
            uint256 discountFactor = WAD - _marketData.growth * _marketData.maturity.zeroFloorSub(block.timestamp);
            assets += newNetCredit.mulDivDown(discountFactor, WAD);
        }
        return assets;
    }
}
