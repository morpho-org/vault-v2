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
import {
    IMidnightAdapterBase,
    IMidnightAdapterStaticTyping,
    MarketData,
    MaturityData
} from "./interfaces/IMidnightAdapter.sol";
import {DurationsLib} from "./libraries/DurationsLib.sol";

/// @dev Approximates held assets by linearly accounting for interest per market.
/// @dev Growth is rounded down. Interest excluded from growth is realized immediately.
/// @dev Losses are immediately accounted in realAssets() minus a discount applied to the remaining interest to be earned, in proportion to the relative sizes of the loss and the adapter's position in the market hit by the loss.
/// @dev The adapter must have the allocator role in its parent vault to buy.
/// @dev The adapter must have the allocator or sentinel role to withdraw to the vault and to sell (except through forceDeallocate).
/// @dev Buy offers must set callbackData to abi.encode(adapter, data) to select where the liquidity will be deallocated, or to "" to take the liquidity in the vault's idle funds.
/// @dev For self-funding, data is abi.encode(fundingMarket).
/// @dev Before adding the adapter to the vault, its timelocks must be properly set.
///
/// TIMELOCKS
/// @dev The system is the same as the one used in VaultV2. Dev comments in VaultV2.sol on timelocks also apply here.
contract MidnightAdapter is IMidnightAdapterStaticTyping {
    using MathLib for uint256;
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
    uint256 public maxTtm;
    mapping(address subRatifier => bool) public isSubRatifier;
    /// @dev Zero may still prevent the adapter from taking buy offers priced at 1 on a market with a nonzero settlement fee.
    /// @dev Enforced on maker and taker sales before maturity only.
    mapping(bytes32 collateralParamsHash => uint256) public maxSellRate;

    /* ACCOUNTING */

    /// @dev Takers of offers of the adapter can fill slots with dust takes.
    uint8 public constant MAX_MARKETS = 250;

    bytes32[] public marketIds;
    /// @dev Maturities holding net credit. Bounded by marketIds.length, since a maturity holds net credit only while one of its markets does.
    uint48[] public maturities;
    /// @dev Net credit last reported to the vault's caps.
    mapping(bytes32 marketId => MarketData) public marketData;
    /// @dev Net credit last reported to the vault's caps, aggregated per maturity.
    mapping(uint256 maturity => MaturityData) public maturityData;
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

    function marketIdsLength() external view returns (uint256) {
        return marketIds.length;
    }

    function maturitiesLength() external view returns (uint256) {
        return maturities.length;
    }

    /// @dev Returns the durations that can be capped.
    /// @dev A market position fills the cap of every duration <= its current time to maturity, so it stops filling a duration's cap as soon as it falls below it.
    function durations() public view returns (uint256[] memory) {
        uint256[] memory _durations = new uint256[](durationsLength);
        for (uint256 i = 0; i < durationsLength; i++) {
            _durations[i] = packedDurations.get(i);
        }
        return _durations;
    }

    /// @dev Id of the vault cap limiting the adapter's exposure to positions with at least `duration` left to maturity.
    /// @dev The vault stores the caps of these ids, so they keep its timelocks and roles, but it never records allocation for them: the adapter checks them itself in onBuy.
    function durationId(uint256 duration) public view returns (bytes32) {
        return keccak256(abi.encode("duration", address(this), duration));
    }

    /// @dev Returns the net credit held at or beyond each duration, using the current times to maturity.
    /// @dev Entry i sums the net credit of the maturities that are at least durations()[i] away, so entries are non-increasing.
    /// @dev Losses and pending sales stay counted until the corresponding market is updated, so entries are an upper bound of the adapter's exposure.
    function durationAllocations() public view returns (uint256[] memory allocations) {
        allocations = new uint256[](durationsLength);
        uint256 length = maturities.length;
        for (uint256 i = 0; i < length; i++) {
            uint256 maturity = maturities[i];
            uint256 netCredit = maturityData[maturity].netCredit;
            uint256 count = durationCount(maturity);
            for (uint256 j = 0; j < count; j++) {
                allocations[j] += netCredit;
            }
        }
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
        // Gates, RCF threshold and collaterals will be checked through vault ids, durations against their caps in onBuy.
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

    /* CURATOR FUNCTIONS */

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

    function setMinBuyRate(uint256 newMinBuyRate) external {
        require(msg.sender == IVaultV2(parentVault).curator(), NotAuthorized());
        minBuyRate = newMinBuyRate;
        emit SetMinBuyRate(newMinBuyRate);
    }

    function setMaxTtm(uint256 newMaxTtm) external {
        timelocked();
        maxTtm = newMaxTtm;
        emit SetMaxTtm(newMaxTtm);
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

        // forge-lint: disable-next-item(reentrancy-no-eth) withdraw does not reenter.
        IMidnight(midnight).withdraw(market, withdrawnAssets, address(this), address(this));
        int256 change = updateMarket(marketId, market, currentNetCredit(marketId));

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

    /* ACCRUAL */

    function realAssets() external view returns (uint256) {
        uint256 assets;
        uint256 length = marketIds.length;
        for (uint256 i = 0; i < length; i++) {
            bytes32 marketId = marketIds[i];
            MarketData memory _marketData = marketData[marketId];
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

            // Skip onSell since we are already in a deallocate call.
            // forge-lint: disable-next-item(reentrancy-no-eth) the buyer's callback cannot touch this locked market.
            IMidnight(midnight).take(offer, ratifierData, assets, address(this), caller, address(0), hex"");
            SafeERC20Lib.safeTransferFrom(asset, caller, address(this), assets);
            int256 change = updateMarket(marketId, offer.market, currentNetCredit(marketId));

            // forge-lint: disable-next-item(unsafe-typecast) change <= 0 when no credit is bought.
            emit ForceDeallocate(marketId, assets, uint256(-change));
            return (ids(offer.market), change);
        } else {
            require(caller == address(this), SelfAllocationOnly());
            returnExactBytes(data);
        }
    }

    /* MIDNIGHT CALLBACKS */

    /// @dev Between updateMarket and vault.allocate's transfer, realAssets() includes the purchase but the vault has not paid yet.
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

        // Cache corrected net credit before call to allocate
        uint128 newNetCredit = currentNetCredit(marketId);
        (overridenMarketId, overridenMarketNetCredit) = (marketId, newNetCredit - boughtNetCredit);
        IVaultV2(parentVault).accrueInterest();
        (overridenMarketId, overridenMarketNetCredit) = (0, 0);

        if (block.timestamp < market.maturity && boughtNetCredit > 0) {
            uint256 addedAssetsWadPerSecond =
                (boughtNetCredit - paidAssets).mulDivDown(WAD, market.maturity - block.timestamp);
            require(addedAssetsWadPerSecond >= minBuyRate * paidAssets, BuyRateTooLow());

            MarketData storage _marketData = marketData[marketId];
            uint256 oldAssetsWadPerSecond = (newNetCredit - boughtNetCredit) * _marketData.growth;
            // forge-lint: disable-next-item(unsafe-typecast) growth <= WAD < 2**64.
            _marketData.growth = uint64((oldAssetsWadPerSecond + addedAssetsWadPerSecond) / newNetCredit);
        }

        int256 change = updateMarket(marketId, market, newNetCredit);
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

        // Check the resulting exposure after the buy and any funding withdrawal, on the durations it reaches: exposure to the others only decreases with time.
        // Duration ids store configuration in the vault only; they are not returned by ids(market).
        uint256 checkedDurations = durationCount(market.maturity);
        uint256[] memory allocations = durationAllocations();
        uint256 totalAssets = IVaultV2(parentVault).firstTotalAssets();
        for (uint256 i = 0; i < checkedDurations; i++) {
            bytes32 id = durationId(packedDurations.get(i));
            require(allocations[i] <= IVaultV2(parentVault).absoluteCap(id), DurationAbsoluteCapExceeded());
            uint256 relativeCap = IVaultV2(parentVault).relativeCap(id);
            require(
                relativeCap == WAD || allocations[i] <= totalAssets.mulDivDown(relativeCap, WAD),
                DurationRelativeCapExceeded()
            );
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

        int256 change = updateMarket(marketId, market, newNetCredit);
        IVaultV2(parentVault).deallocate(address(this), abi.encode(ids(market), change), sellerAssets);

        // forge-lint: disable-next-item(unsafe-typecast) change <= 0 when no credit is bought.
        emit Sell(marketId, sellerAssets, uint256(-change));
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

    /// @dev Updates market and maturity net credit and inserts or removes the market from marketIds and its maturity from maturities as needed.
    /// @return change The change in net credit to report to the vault's caps.
    function updateMarket(bytes32 marketId, Market memory market, uint128 newNetCredit)
        internal
        returns (int256 change)
    {
        MarketData storage _marketData = marketData[marketId];
        uint256 storedNetCredit = _marketData.netCredit;
        _marketData.netCredit = newNetCredit;
        if (newNetCredit == 0 && storedNetCredit > 0) {
            bytes32 lastMarketId = marketIds[marketIds.length - 1];
            marketIds[_marketData.index] = lastMarketId;
            marketData[lastMarketId].index = _marketData.index;
            marketIds.pop();
        } else if (storedNetCredit == 0 && newNetCredit > 0) {
            require(marketIds.length < MAX_MARKETS, TooManyMarkets());
            _marketData.maturity = market.maturity.toUint48();
            // forge-lint: disable-next-item(unsafe-typecast) marketIds.length < MAX_MARKETS.
            _marketData.index = uint8(marketIds.length);
            marketIds.push(marketId);
        }

        MaturityData storage _maturityData = maturityData[market.maturity];
        uint256 storedMaturityNetCredit = _maturityData.netCredit;
        uint256 newMaturityNetCredit = storedMaturityNetCredit + newNetCredit - storedNetCredit;
        _maturityData.netCredit = newMaturityNetCredit.toUint128();
        // Net credit is never negative, so a maturity holds net credit iff at least one of its markets does.
        if (newMaturityNetCredit == 0 && storedMaturityNetCredit > 0) {
            uint48 lastMaturity = maturities[maturities.length - 1];
            maturities[_maturityData.index] = lastMaturity;
            maturityData[lastMaturity].index = _maturityData.index;
            maturities.pop();
        } else if (storedMaturityNetCredit == 0 && newMaturityNetCredit > 0) {
            // forge-lint: disable-next-item(unsafe-typecast) maturities.length <= marketIds.length <= MAX_MARKETS.
            _maturityData.index = uint8(maturities.length);
            maturities.push(market.maturity.toUint48());
        }

        emit UpdateMarket(marketId, _marketData.netCredit, _marketData.growth);
        // forge-lint: disable-next-item(unsafe-typecast) both net credit values fit in uint128.
        change = int256(uint256(newNetCredit)) - int256(storedNetCredit);
    }

    /// @dev Returns the number of durations in packedDurations that are at most the time to maturity.
    function durationCount(uint256 maturity) internal view returns (uint8 count) {
        uint256 timeToMaturity = maturity.zeroFloorSub(block.timestamp);
        while (count < durationsLength && timeToMaturity >= packedDurations.get(count)) count++;
    }

    function ids(Market memory market) public view returns (bytes32[] memory) {
        bytes32[] memory idsArray = new bytes32[](2 + market.collateralParams.length * 2);

        uint256 j;
        idsArray[j++] = adapterId;
        idsArray[j++] =
            keccak256(abi.encode("marketConfig", market.enterGate, market.liquidatorGate, market.rcfThreshold));
        for (uint256 i = 0; i < market.collateralParams.length; i++) {
            idsArray[j++] = keccak256(abi.encode("collateralToken", market.collateralParams[i].token));
            idsArray[j++] = keccak256(abi.encode("collateralParams", market.collateralParams[i]));
        }

        return idsArray;
    }
}
