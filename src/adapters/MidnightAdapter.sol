// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Morpho Association
pragma solidity 0.8.34;

import {IMidnight, Offer, Market} from "lib/midnight/src/interfaces/IMidnight.sol";
import {IRatifier} from "lib/midnight/src/interfaces/IRatifier.sol";
import {IdLib} from "lib/midnight/src/libraries/IdLib.sol";
import {MAX_TICK} from "lib/midnight/src/libraries/TickLib.sol";
import {CALLBACK_SUCCESS} from "lib/midnight/src/libraries/ConstantsLib.sol";
import {IERC20} from "../interfaces/IERC20.sol";
import {SafeERC20Lib} from "../libraries/SafeERC20Lib.sol";
import {MathLib} from "../libraries/MathLib.sol";
import {WAD} from "../libraries/ConstantsLib.sol";
import {IVaultV2} from "../interfaces/IVaultV2.sol";
import {IMidnightAdapter, MarketData, MaturityData} from "./interfaces/IMidnightAdapter.sol";
import {DurationsLib} from "./libraries/DurationsLib.sol";

/// @dev Approximates held assets by linearly accounting for interest per market.
/// @dev Growth is rounded down. Interest excluded from growth is realized immediately.
/// @dev Losses are immediately accounted in realAssets() minus a discount applied to the remaining interest to be
/// earned, in proportion to the relative sizes of the loss and the adapter's position in the market hit by the loss.
/// @dev The adapter must have the allocator role in its parent vault to buy.
/// @dev The adapter must have the allocator or sentinel role to withdraw to the vault, to update duration caps, and to
/// sell (except through forceDeallocate).
/// @dev Buy offers must set callbackData to abi.encode(adapter, data) to select where the liquidity will be
/// deallocated, or to "" to take the liquidity in the vault's idle funds.
/// @dev For self-funding, data is abi.encode(fundingMarket).
/// @dev Before adding the adapter to the vault, its timelocks must be properly set.
///
/// TIMELOCKS
/// @dev The system is the same as the one used in VaultV2. Dev comments in VaultV2.sol on timelocks also apply here.
contract MidnightAdapter is IMidnightAdapter {
    using MathLib for uint256;
    using MathLib for uint128;
    using MathLib for uint48;
    using DurationsLib for bytes32;

    /* IMMUTABLES */

    address public immutable asset;
    address public immutable parentVault;
    address public immutable midnight;
    bytes32 public immutable adapterId;
    /// @dev Durations that can be used to cap the time to maturity.
    /// @dev Sorted in ascending order.
    bytes32 public immutable packedDurations;
    uint256 public immutable durationsLength;

    /* TIMELOCKS STORAGE */

    mapping(bytes4 selector => uint256) public timelock;
    mapping(bytes4 selector => bool) public abdicated;
    mapping(bytes data => uint256) public executableAt;

    /* MANAGEMENT */

    address public skimRecipient;
    /// @dev Minimum net simple interest rate per second, WAD-scaled, enforced on maker and taker buys before maturity.
    uint256 public minBuyRate;
    mapping(address subRatifier => bool) public isSubRatifier;
    /// @dev Zero may still prevent the adapter from taking buy offers priced at 1 on a market with a nonzero settlement
    /// fee.
    /// @dev Enforced on maker and taker sales before maturity only.
    mapping(bytes32 collateralParamsHash => uint256) public maxSellRate;

    /* ACCOUNTING */

    /// @dev Takers of offers of the adapter can fill slots with dust takes.
    uint8 public constant MAX_MARKETS = 250;
    // @dev A shortfall is the negative delta if any between the amortized value of sold credit and the actual sales
    // proceeds.
    uint256 public constant SHORTFALL_REFILL_PERIOD = 1 days;
    uint256 public constant MAX_SHORTFALL_RATIO = 0.005e18; // 0.5%

    bytes32[] public marketIds;
    /// @dev Net credit last reported to the vault's caps.
    mapping(bytes32 marketId => MarketData) internal _marketData;
    mapping(uint256 timestamp => MaturityData) internal _maturities;
    uint256 public totalNetCredit;
    uint128 public shortfallAllowance;
    uint48 public shortfallUpdatedAt;
    bytes32 transient overridenMarketId;
    uint256 transient overridenMarketNetCredit;
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

    /* GETTERS */

    function marketData(bytes32 marketId) external view returns (MarketData memory) {
        return _marketData[marketId];
    }

    function maturities(uint256 date) public view returns (MaturityData memory) {
        return _maturities[date];
    }

    function marketIdsLength() external view returns (uint256) {
        return marketIds.length;
    }

    /// @dev Returns the durations that can be capped.
    /// @dev A market position fills the cap of any duration that was <= its time to maturity at the first buy of its
    /// maturity, or at the last updateDurationCaps call for its maturity.
    function durations() public view returns (uint256[] memory) {
        uint256[] memory _durations = new uint256[](durationsLength);
        for (uint256 i = 0; i < durationsLength; i++) {
            _durations[i] = packedDurations.get(i);
        }
        return _durations;
    }

    /* RATIFIERS */

    /// @dev Sub-ratifiers define how allocator offers are authorized.
    function addSubRatifier(address subRatifier) external {
        timelocked();
        isSubRatifier[subRatifier] = true;
        emit AddSubRatifier(subRatifier);
    }

    function removeSubRatifier(address subRatifier) external {
        require(
            IVaultV2(parentVault).isAllocator(msg.sender) || IVaultV2(parentVault).isSentinel(msg.sender),
            NotAuthorized()
        );
        isSubRatifier[subRatifier] = false;
        emit RemoveSubRatifier(msg.sender, subRatifier);
    }

    function isRatified(Offer memory offer, bytes memory data, address taker) external view returns (bytes32) {
        require(!IMidnight(midnight).liquidationLocked(IdLib.toId(offer.market), address(this)), SellInProgress());
        // Gates, RCF threshold, collaterals and durations will be checked through vault ids.
        require(offer.market.loanToken == asset, LoanAssetMismatch());
        require(offer.maker == address(this), IncorrectMaker());
        require(offer.callback == address(this), IncorrectCallbackAddress());
        // For buy offers, Midnight enforces receiverIfMakerIsSeller == address(0).
        require(offer.buy || offer.receiverIfMakerIsSeller == address(this), IncorrectReceiver());

        (address subRatifier, bytes memory subRatifierData) = abi.decode(data, (address, bytes));
        require(isSubRatifier[subRatifier], SubRatifierFailed());
        return IRatifier(subRatifier).isRatified(offer, subRatifierData, taker);
    }

    /* TIMELOCKS FUNCTIONS */

    /// @dev Will revert if the timelock value is type(uint256).max or any value that overflows when added to the block
    /// timestamp.
    function submit(bytes calldata data) external {
        require(msg.sender == IVaultV2(parentVault).curator(), NotAuthorized());
        require(executableAt[data] == 0, DataAlreadyPending());

        // forge-lint: disable-next-item(unsafe-typecast) we explicitly want only the first bytes4.
        bytes4 selector = bytes4(data);
        // forge-lint: disable-next-item(unsafe-typecast) we explicitly want only the second bytes4.
        uint256 _timelock =
            selector == IMidnightAdapter.decreaseTimelock.selector ? timelock[bytes4(data[4:8])] : timelock[selector];
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

    /* CURATOR FUNCTIONS */

    /// @dev This function requires great caution because it can irreversibly disable submit for a selector.
    /// @dev Existing pending operations submitted before increasing a timelock can still be executed at the initial
    /// executableAt.
    function increaseTimelock(bytes4 selector, uint256 newDuration) external {
        timelocked();
        require(selector != IMidnightAdapter.decreaseTimelock.selector, AutomaticallyTimelocked());
        require(newDuration >= timelock[selector], TimelockNotIncreasing());

        timelock[selector] = newDuration;
        emit IncreaseTimelock(selector, newDuration);
    }

    function decreaseTimelock(bytes4 selector, uint256 newDuration) external {
        timelocked();
        require(selector != IMidnightAdapter.decreaseTimelock.selector, AutomaticallyTimelocked());
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

    function setMinBuyRate(uint256 newMinBuyRate) external {
        require(msg.sender == IVaultV2(parentVault).curator(), NotAuthorized());
        minBuyRate = newMinBuyRate;
        emit SetMinBuyRate(newMinBuyRate);
    }

    /// @dev Help prevent operational errors when selling.
    function setMaxSellRate(bytes32 collateralParamsHash, uint256 newMaxSellRate) external {
        require(msg.sender == IVaultV2(parentVault).curator(), NotAuthorized());
        maxSellRate[collateralParamsHash] = newMaxSellRate;
        emit SetMaxSellRate(msg.sender, collateralParamsHash, newMaxSellRate);
    }

    function setSkimRecipient(address newSkimRecipient) external {
        timelocked();
        skimRecipient = newSkimRecipient;
        emit SetSkimRecipient(newSkimRecipient);
    }

    /* SKIM FUNCTIONS */

    /// @dev Skims the adapter's balance of `token` and sends it to `skimRecipient`.
    /// @dev This is useful to handle rewards that the adapter has earned.
    function skim(address token) external {
        require(msg.sender == skimRecipient, NotAuthorized());
        uint256 balance = IERC20(token).balanceOf(address(this));
        SafeERC20Lib.safeTransfer(token, skimRecipient, balance);
        emit Skim(token, balance);
    }

    /* VAULT ALLOCATORS FUNCTIONS */

    function withdrawToVault(Market memory market, uint256 withdrawnAssets) public {
        bytes32 marketId = IdLib.toId(market);
        require(!IMidnight(midnight).liquidationLocked(marketId, address(this)), SellInProgress());
        uint128 oldNetCredit = currentNetCredit(marketId);

        // forge-lint: disable-next-item(reentrancy-no-eth) withdraw does not reenter.
        IMidnight(midnight).withdraw(market, withdrawnAssets, address(this), address(this));
        int256 change = updateMarket(marketId, market, oldNetCredit, currentNetCredit(marketId));

        // forge-lint: disable-next-item(reentrancy-no-eth) deallocate in this adapter does not call withdrawToVault.
        IVaultV2(parentVault).deallocate(address(this), abi.encode(ids(market), change), withdrawnAssets);
        // forge-lint: disable-next-item(unsafe-typecast) change <= 0 when no credit is bought.
        emit WithdrawToVault(marketId, withdrawnAssets, uint256(-change));
    }

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

    /// @dev Remove the maturity allocation from the duration ids that are > its time to maturity.
    function updateDurationCaps(uint256 maturity) external {
        MaturityData storage maturityData = _maturities[maturity];
        uint256 maturityNetCredit = maturityData.netCredit;
        uint256 oldDurationCount = maturityData.durationCount;
        uint8 newDurationCount = durationCount(maturity);
        // VaultV2.deallocate requires allocation > 0 for each returned id.
        if (newDurationCount < oldDurationCount && maturityNetCredit > 0) {
            maturityData.durationCount = newDurationCount;
            emit UpdateDurationCaps(maturity, newDurationCount, maturityNetCredit);
            bytes32[] memory zeroedDurationsIds = new bytes32[](oldDurationCount - newDurationCount);
            for (uint256 i = 0; i < zeroedDurationsIds.length; i++) {
                zeroedDurationsIds[i] = keccak256(abi.encode("duration", packedDurations.get(newDurationCount + i)));
            }
            // forge-lint: disable-next-item(unsafe-typecast) net credit fits in uint128.
            IVaultV2(parentVault)
                .deallocate(address(this), abi.encode(zeroedDurationsIds, -int256(maturityNetCredit)), 0);
        }
    }

    /* ACCRUAL */

    function realAssets() external view returns (uint256) {
        uint256 assets;
        uint256 length = marketIds.length;
        for (uint256 i = 0; i < length; i++) {
            bytes32 marketId = marketIds[i];
            MarketData storage data = _marketData[marketId];
            uint256 newNetCredit;
            if (marketId == overridenMarketId) {
                newNetCredit = overridenMarketNetCredit;
            } else {
                require(!IMidnight(midnight).liquidationLocked(marketId, address(this)), OtherSellInProgress());
                newNetCredit = currentNetCredit(marketId);
            }
            uint256 discountFactor = WAD - data.growth * data.maturity.zeroFloorSub(block.timestamp);
            assets += newNetCredit.mulDivDown(discountFactor, WAD);
        }
        return assets;
    }

    /* ALLOCATION FUNCTIONS */

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

    /// @dev Can be called by this adapter from a sell callback, a withdraw, or a duration caps update.
    /// @dev Can be called by anyone through forceDeallocate to trigger a sell take by the adapter.
    /// @dev forceDeallocate callers must approve for asset transfer to cover the settlement fee
    function deallocate(bytes memory data, uint256 sellerAssets, bytes4 messageSig, address caller)
        external
        returns (bytes32[] memory, int256)
    {
        require(msg.sender == parentVault, NotAuthorized());
        if (messageSig == IVaultV2.forceDeallocate.selector) {
            (Offer memory offer, bytes memory ratifierData) = abi.decode(data, (Offer, bytes));
            require(
                offer.buy && offer.market.loanToken == asset && offer.tick == MAX_TICK && offer.callback == address(0),
                IncorrectOffer()
            );

            bytes32 marketId = IdLib.toId(offer.market);
            require(!IMidnight(midnight).liquidationLocked(marketId, address(this)), SellInProgress());
            IVaultV2(parentVault).accrueInterest();
            uint128 oldNetCredit = currentNetCredit(marketId);

            // Skip onSell since we are already in a deallocate call.
            // forge-lint: disable-next-item(reentrancy-no-eth) view reentry is possible through a ratifier.
            (, uint256 receivedAssets) = IMidnight(midnight)
                .take(offer, ratifierData, sellerAssets, address(this), address(this), address(0), hex"");
            uint256 settlementFee = sellerAssets - receivedAssets;
            if (settlementFee > 0) SafeERC20Lib.safeTransferFrom(asset, caller, address(this), settlementFee);
            int256 change = updateMarket(marketId, offer.market, oldNetCredit, currentNetCredit(marketId));

            // forge-lint: disable-next-item(unsafe-typecast) change <= 0 when no credit is bought.
            emit ForceDeallocate(marketId, sellerAssets, uint256(-change));
            return (ids(offer.market), change);
        } else {
            require(caller == address(this), SelfAllocationOnly());
            returnExactBytes(data);
        }
    }

    /* MIDNIGHT CALLBACKS */

    /// @dev Between updateMarket and vault.allocate's transfer, realAssets() includes the purchase but the vault has
    /// not paid yet.
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
        uint256 boughtNetCredit = boughtCredit - buyPendingFeeIncrease;
        require(boughtNetCredit >= paidAssets, BuyAtLoss());

        // Cache corrected net credit before call to allocate
        uint128 newNetCredit = currentNetCredit(marketId);
        (overridenMarketId, overridenMarketNetCredit) = (marketId, newNetCredit - boughtNetCredit);
        IVaultV2(parentVault).accrueInterest();
        (overridenMarketId, overridenMarketNetCredit) = (0, 0);

        if (block.timestamp < market.maturity && boughtNetCredit > 0) {
            uint256 addedAssetsWadPerSecond =
                (boughtNetCredit - paidAssets).mulDivDown(WAD, market.maturity - block.timestamp);
            require(addedAssetsWadPerSecond >= minBuyRate * paidAssets, BuyRateTooLow());

            MarketData storage data = _marketData[marketId];
            uint256 oldAssetsWadPerSecond = (newNetCredit - boughtNetCredit) * data.growth;
            // forge-lint: disable-next-item(unsafe-typecast) growth <= WAD < 2**64.
            data.growth = uint64((oldAssetsWadPerSecond + addedAssetsWadPerSecond) / newNetCredit);
        }

        MaturityData storage maturityData = _maturities[market.maturity];
        if (maturityData.netCredit == 0) maturityData.durationCount = durationCount(market.maturity);
        int256 change = updateMarket(marketId, market, newNetCredit - boughtNetCredit, newNetCredit);
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

        // forge-lint: disable-next-item(reentrancy-no-eth) reentry is expected.
        IVaultV2(parentVault).allocate(address(this), abi.encode(ids(market), change), paidAssets);

        // forge-lint: disable-next-item(unsafe-typecast) boughtNetCredit and the credit loss fit in uint128.
        emit Buy(marketId, paidAssets, boughtNetCredit, uint256(int256(boughtNetCredit) - change));
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

        uint128 newNetCredit = currentNetCredit(marketId);
        uint256 soldNetCredit = soldCredit - sellPendingFeeDecrease;
        if (block.timestamp < market.maturity && soldNetCredit > sellerAssets) {
            require(
                (soldNetCredit - sellerAssets).mulDivUp(WAD, (market.maturity - block.timestamp) * sellerAssets)
                    <= maxSellRate[keccak256(abi.encode(market.collateralParams))],
                SellRateTooHigh()
            );
        }

        int256 change = updateMarket(marketId, market, newNetCredit + soldNetCredit, newNetCredit);

        uint256 discountFactor = WAD - _marketData[marketId].growth * market.maturity.zeroFloorSub(block.timestamp);
        uint256 assetsBefore = (newNetCredit + soldNetCredit).mulDivDown(discountFactor, WAD);
        uint256 assetsAfter = newNetCredit.mulDivDown(discountFactor, WAD);
        uint256 saleShortfall = (assetsBefore - assetsAfter).zeroFloorSub(sellerAssets);
        if (block.timestamp < market.maturity) {
            shortfallAllowance -= saleShortfall.toUint128();
        }
        IVaultV2(parentVault).deallocate(address(this), abi.encode(ids(market), change), sellerAssets);

        // forge-lint: disable-next-item(unsafe-typecast) change <= 0 when no credit is bought.
        emit Sell(marketId, sellerAssets, uint256(-change), saleShortfall);
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

    /// @dev Updates market and maturity net credit and inserts or removes the market from marketIds as needed.
    /// @return change The change in net credit to report to the vault's caps.
    function updateMarket(bytes32 marketId, Market memory market, uint256 oldNetCredit, uint128 newNetCredit)
        internal
        returns (int256 change)
    {
        MarketData storage data = _marketData[marketId];
        uint256 storedNetCredit = data.netCredit;
        uint256 allowanceCap = (totalNetCredit - storedNetCredit + oldNetCredit).mulDivDown(MAX_SHORTFALL_RATIO, WAD);
        shortfallAllowance = MathLib.min(
                allowanceCap,
                shortfallAllowance
                    + allowanceCap.mulDivDown(block.timestamp - shortfallUpdatedAt, SHORTFALL_REFILL_PERIOD)
            )
            .toUint128();
        shortfallUpdatedAt = block.timestamp.toUint48();

        data.netCredit = newNetCredit;
        totalNetCredit = totalNetCredit + newNetCredit - storedNetCredit;
        _maturities[market.maturity].netCredit =
            (uint256(_maturities[market.maturity].netCredit) + newNetCredit - storedNetCredit).toUint128();
        if (newNetCredit == 0 && storedNetCredit > 0) {
            bytes32 lastMarketId = marketIds[marketIds.length - 1];
            marketIds[data.index] = lastMarketId;
            _marketData[lastMarketId].index = data.index;
            marketIds.pop();
        } else if (storedNetCredit == 0 && newNetCredit > 0) {
            require(marketIds.length < MAX_MARKETS, TooManyMarkets());
            data.maturity = market.maturity.toUint48();
            // forge-lint: disable-next-item(unsafe-typecast) marketIds.length < MAX_MARKETS.
            data.index = uint8(marketIds.length);
            marketIds.push(marketId);
        }
        emit UpdateMarket(marketId, data, shortfallAllowance);
        // forge-lint: disable-next-item(unsafe-typecast) both net credit values fit in uint128.
        change = int256(uint256(newNetCredit)) - int256(storedNetCredit);
    }

    /// @dev Returns the number of durations in packedDurations that are at most the time to maturity.
    function durationCount(uint256 maturity) internal view returns (uint8 count) {
        uint256 timeToMaturity = maturity.zeroFloorSub(block.timestamp);
        while (count < durationsLength && timeToMaturity >= packedDurations.get(count)) count++;
    }

    function ids(Market memory market) public view returns (bytes32[] memory) {
        uint256 durationsCount = _maturities[market.maturity].durationCount;

        bytes32[] memory idsArray = new bytes32[](2 + market.collateralParams.length * 2 + durationsCount);

        uint256 j;
        idsArray[j++] = adapterId;
        idsArray[j++] =
            keccak256(abi.encode("marketConfig", market.enterGate, market.liquidatorGate, market.rcfThreshold));
        for (uint256 i = 0; i < market.collateralParams.length; i++) {
            idsArray[j++] = keccak256(abi.encode("collateralToken", market.collateralParams[i].token));
            idsArray[j++] = keccak256(abi.encode("collateralParams", market.collateralParams[i]));
        }
        for (uint256 i = 0; i < durationsCount; i++) {
            idsArray[j++] = keccak256(abi.encode("duration", packedDurations.get(i)));
        }

        return idsArray;
    }
}
