// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Morpho Association
pragma solidity 0.8.34;

import {IMidnight, Offer, Market} from "lib/midnight/src/interfaces/IMidnight.sol";
import {IRatifier} from "lib/midnight/src/interfaces/IRatifier.sol";
import {IdLib} from "lib/midnight/src/libraries/IdLib.sol";
import {MAX_TICK} from "lib/midnight/src/libraries/TickLib.sol";
import {CALLBACK_SUCCESS} from "lib/midnight/src/libraries/ConstantsLib.sol";
import {TakeAmountsLib} from "lib/midnight/src/periphery/libraries/TakeAmountsLib.sol";
import {IERC20} from "../interfaces/IERC20.sol";
import {SafeERC20Lib} from "../libraries/SafeERC20Lib.sol";
import {MathLib} from "../libraries/MathLib.sol";
import {IVaultV2} from "../interfaces/IVaultV2.sol";
import {IMidnightAdapter, MarketData, MaturityData, IAdapter} from "./interfaces/IMidnightAdapter.sol";
import {DurationsLib} from "./libraries/DurationsLib.sol";

/// @dev Values all tracked markets after position losses and amortizes purchase discounts linearly until maturity.
/// @dev The vault's max rate further limits the distribution of interest.
/// @dev The vault must accrue interest before an adapter offer is taken, in the same transaction, so its share price
/// cannot reflect an unsettled trade during Midnight's callbacks.
/// @dev The adapter must have the allocator role in its parent vault to buy, and the allocator or sentinel role to
/// make sell offers, to withdraw to the vault and to update duration caps.
/// @dev Buy offers must set callbackData to abi.encode(adapter, data) to select where the liquidity will be
/// deallocated, or to "" to take the liquidity in the vault's idle funds.
/// @dev Before adding the adapter to the vault, its timelocks must be properly set.
///
/// TIMELOCKS
/// @dev The system is the same as the one used in VaultV2. Dev comments in VaultV2.sol on timelocks also apply here.
contract MidnightAdapter is IMidnightAdapter {
    using MathLib for uint256;
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
    /// @dev Remaining allowance for losses not covered by the vault's buffer, in asset units.
    uint256 public skipBufferAllowance;
    mapping(address subRatifier => bool) public isSubRatifier;

    /* ACCOUNTING */

    /// @dev Takers of offers of the adapter can fill slots with dust takes.
    uint8 public constant MAX_MARKETS = 250;

    bytes32[] public marketIds;
    /// @dev Net credit last reported to the vault's caps and its associated loss factor.
    mapping(bytes32 marketId => MarketData) internal _markets;
    mapping(uint256 timestamp => MaturityData) internal _maturities;
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

    function netCredit(bytes32 marketId) external view returns (uint128) {
        return _markets[marketId].netCredit;
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

    /// @dev Sub-ratifiers can approve any offer of the adapter that passes the checks of isRatified, akin to
    /// allocators signing offer trees.
    function setIsSubRatifier(address subRatifier, bool newIsSubRatifier) external {
        require(
            IVaultV2(parentVault).isAllocator(msg.sender)
                || (!newIsSubRatifier && IVaultV2(parentVault).isSentinel(msg.sender)),
            NotAuthorized()
        );
        isSubRatifier[subRatifier] = newIsSubRatifier;
        emit SetIsSubRatifier(subRatifier, newIsSubRatifier);
    }

    function isRatified(Offer memory offer, bytes memory data, address taker) external view returns (bytes32) {
        require(IVaultV2(parentVault).firstTotalAssets() != 0, VaultNotAccrued());
        // Collaterals will be checked through vault ids.
        require(offer.market.loanToken == asset, LoanAssetMismatch());
        require(offer.maker == address(this), IncorrectMaker());
        require(offer.callback == address(this), IncorrectCallbackAddress());
        // For buy offers, Midnight enforces receiverIfMakerIsSeller == address(0).
        require(offer.buy || offer.receiverIfMakerIsSeller == address(this), IncorrectReceiver());
        require(offer.buy || offer.reduceOnly, NoDebtCreation());

        (address subRatifier, bytes memory subData) = abi.decode(data, (address, bytes));
        require(isSubRatifier[subRatifier], SubRatifierUnauthorized());
        return IRatifier(subRatifier).isRatified(offer, subData, taker);
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

    function setSkipBufferAllowance(uint256 newSkipBufferAllowance) external {
        timelocked();
        skipBufferAllowance = newSkipBufferAllowance;
        emit SetSkipBufferAllowance(newSkipBufferAllowance);
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

    function withdrawToVault(Market memory market, uint256 withdrawnAssets) external {
        bytes32 marketId = IdLib.toId(market);
        require(
            IVaultV2(parentVault).isAllocator(msg.sender) || IVaultV2(parentVault).isSentinel(msg.sender),
            NotAuthorized()
        );

        IVaultV2(parentVault).accrueInterest();

        // forge-lint: disable-next-item(reentrancy-no-eth) withdraw does not call back.
        IMidnight(midnight).withdraw(market, withdrawnAssets, address(this), address(this));
        int256 change = updateMarket(marketId, market, 0, 0);

        IVaultV2(parentVault).deallocate(address(this), abi.encode(ids(market), change), withdrawnAssets);
        // forge-lint: disable-next-item(unsafe-typecast) change <= 0 when no credit is bought.
        emit WithdrawToVault(marketId, withdrawnAssets, uint256(-change));
    }

    function take(Offer memory offer, bytes memory ratifierData, uint256 units) external {
        require(IVaultV2(parentVault).isAllocator(msg.sender), NotAuthorized());
        require(offer.market.loanToken == asset, LoanAssetMismatch());
        IVaultV2(parentVault).accrueInterest();
        IMidnight(midnight)
            .take(
                offer, ratifierData, units, address(this), offer.buy ? address(this) : address(0), address(this), hex""
            );
    }

    /// @dev Remove the maturity allocation from the duration ids that are > its time to maturity.
    function updateDurationCaps(uint256 maturity) external {
        MaturityData storage maturityData = _maturities[maturity];
        uint256 oldDurationCount = maturityData.durationCount;
        uint256 newDurationCount = durationCount(maturity);
        // VaultV2.deallocate requires allocation > 0 for each returned id.
        if (newDurationCount < oldDurationCount && maturityData.netCredit > 0) {
            // forge-lint: disable-next-item(unsafe-typecast) newDurationCount <= MAX_DURATIONS.
            maturityData.durationCount = uint8(newDurationCount);
            emit UpdateDurationCaps(maturity, newDurationCount, maturityData.netCredit);
            bytes32[] memory zeroedDurationsIds = new bytes32[](oldDurationCount - newDurationCount);
            for (uint256 i = 0; i < zeroedDurationsIds.length; i++) {
                zeroedDurationsIds[i] = keccak256(abi.encode("duration", packedDurations.get(newDurationCount + i)));
            }
            bytes memory data = abi.encode(zeroedDurationsIds, -int256(uint256(maturityData.netCredit)));
            IVaultV2(parentVault).deallocate(address(this), data, 0);
        }
    }

    /* ACCRUAL */

    function realAssets() external view returns (uint256) {
        uint256 assets;
        uint256 length = marketIds.length;
        for (uint256 i = 0; i < length; i++) {
            bytes32 marketId = marketIds[i];
            MarketData memory marketData = _markets[marketId];
            uint256 newNetCredit;
            if (
                marketData.lossFactor == IMidnight(midnight).lossFactor(marketId)
                    && !IMidnight(midnight).liquidationLocked(marketId, address(this))
            ) {
                newNetCredit = marketData.netCredit;
            } else {
                newNetCredit = currentNetCredit(marketId, IMidnight(midnight).toMarket(marketId));
            }
            assets += currentAssets(marketData, uint256(marketData.netCredit) - newNetCredit);
        }
        return assets;
    }

    /* ALLOCATION FUNCTIONS */

    /// @dev Can be called by this adapter from a buy callback.
    function allocate(bytes memory data, uint256, bytes4, address caller)
        external
        view
        returns (bytes32[] memory, int256)
    {
        require(msg.sender == parentVault, NotAuthorized());
        require(caller == address(this), SelfAllocationOnly());
        // Return exactly the data passed to the function.
        assembly ("memory-safe") {
            return(add(data, 32), mload(data))
        }
    }

    /// @dev Can be called by this adapter from a sell callback, a withdraw, or a duration caps update.
    /// @dev Can be called by anyone through forceDeallocate to trigger a sell take by the adapter.
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

            IVaultV2(parentVault).accrueInterest();

            // Skip onSell since we are already in a deallocate call.
            bytes32 marketId = IdLib.toId(offer.market);
            uint256 takeUnits = TakeAmountsLib.sellerAssetsToUnits(midnight, marketId, offer, sellerAssets);
            // forge-lint: disable-next-item(reentrancy-no-eth) view reentry is possible through a ratifier.
            IMidnight(midnight).take(offer, ratifierData, takeUnits, address(this), address(this), address(0), hex"");
            int256 change = updateMarket(marketId, offer.market, 0, 0);

            // forge-lint: disable-next-item(unsafe-typecast) change <= 0 when no credit is bought.
            emit ForceDeallocate(marketId, sellerAssets, uint256(-change));
            return (ids(offer.market), change);
        } else {
            require(caller == address(this), SelfAllocationOnly());
            // Return exactly the data passed to the function.
            assembly ("memory-safe") {
                return(add(data, 32), mload(data))
            }
        }
    }

    /* MIDNIGHT CALLBACKS */

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
        uint256 boughtNetCredit = boughtCredit - buyPendingFeeIncrease;
        require(boughtNetCredit >= paidAssets, BuyAtLoss());

        MaturityData storage maturityData = _maturities[market.maturity];
        // forge-lint: disable-next-item(unsafe-typecast) durationCount <= MAX_DURATIONS.
        if (maturityData.netCredit == 0) maturityData.durationCount = uint8(durationCount(market.maturity));
        int256 change = updateMarket(marketId, market, boughtNetCredit, paidAssets);
        uint256 idleAssets = IERC20(asset).balanceOf(parentVault);
        if (callbackData.length > 0 && paidAssets > idleAssets) {
            (address fundingAdapter, bytes memory fundingData) = abi.decode(callbackData, (address, bytes));
            // forge-lint: disable-next-item(reentrancy-no-eth) the adapter is trusted.
            IVaultV2(parentVault).deallocate(fundingAdapter, fundingData, paidAssets - idleAssets);
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

        uint256 soldNetCredit = soldCredit - sellPendingFeeDecrease;
        MarketData memory beforeUpdate = _markets[marketId];
        uint256 soldAssets = soldNetCredit;
        if (beforeUpdate.netCredit > 0) {
            soldAssets = currentAssets(beforeUpdate, 0).mulDivDown(soldNetCredit, beforeUpdate.netCredit);
        }
        uint256 loss = soldAssets.zeroFloorSub(sellerAssets);
        int256 change = updateMarket(marketId, market, 0, 0);

        IVaultV2(parentVault).deallocate(address(this), abi.encode(ids(market), change), sellerAssets);

        uint256 vaultRealAssetsAfter = IERC20(asset).balanceOf(parentVault);
        uint256 adaptersLength = IVaultV2(parentVault).adaptersLength();
        for (uint256 i = 0; i < adaptersLength; i++) {
            vaultRealAssetsAfter += IAdapter(IVaultV2(parentVault).adapters(i)).realAssets();
        }
        uint256 consumed = MathLib.min(loss, IVaultV2(parentVault).totalAssets().zeroFloorSub(vaultRealAssetsAfter));
        if (consumed > 0) {
            skipBufferAllowance -= consumed;
            emit ConsumeSkipBufferAllowance(consumed);
        }

        // forge-lint: disable-next-item(unsafe-typecast) change <= 0 when no credit is bought.
        emit Sell(marketId, sellerAssets, uint256(-change));
        return CALLBACK_SUCCESS;
    }

    /* INTERNAL FUNCTIONS */

    function currentNetCredit(bytes32 marketId, Market memory market) internal view returns (uint128) {
        (uint128 credit, uint128 pendingFee,) = IMidnight(midnight).updatePositionView(market, marketId, address(this));
        return credit - pendingFee;
    }

    /// @dev Interpolates the position assets to now, then scale them down if the position decreased since the last
    /// update.
    function currentAssets(MarketData memory marketData, uint256 netCreditDecrease) internal view returns (uint256) {
        uint256 remainingNetCredit = uint256(marketData.netCredit) - netCreditDecrease;
        if (marketData.netCredit == 0 || block.timestamp >= marketData.maturity) return remainingNetCredit;
        uint256 futureInterest = (uint256(marketData.netCredit) - marketData.assets)
        .mulDivUp(marketData.maturity - block.timestamp, marketData.maturity - marketData.lastUpdate);
        uint256 assets = marketData.netCredit - futureInterest;
        return assets.mulDivDown(remainingNetCredit, marketData.netCredit);
    }

    /// @dev Returns the change in net credit reported to the vault's caps.
    function updateMarket(bytes32 marketId, Market memory market, uint256 boughtNetCredit, uint256 paidAssets)
        internal
        returns (int256 change)
    {
        MarketData storage marketData = _markets[marketId];
        uint256 oldNetCredit = marketData.netCredit;
        uint128 newNetCredit = currentNetCredit(marketId, market);
        uint256 netCreditDecrease = oldNetCredit + boughtNetCredit - newNetCredit;
        marketData.lossFactor = IMidnight(midnight).lossFactor(marketId);
        // forge-lint: disable-next-item(unsafe-typecast) assets <= newNetCredit <= type(uint128).max.
        marketData.assets = uint128(
            currentAssets(marketData, netCreditDecrease)
                + (block.timestamp < market.maturity ? paidAssets : boughtNetCredit)
        );
        marketData.netCredit = newNetCredit;
        marketData.lastUpdate = block.timestamp.toUint48();
        _maturities[market.maturity].netCredit =
            (uint256(_maturities[market.maturity].netCredit) + newNetCredit - oldNetCredit).toUint128();
        if (newNetCredit == 0 && oldNetCredit > 0) {
            bytes32 lastMarketId = marketIds[marketIds.length - 1];
            marketIds[marketData.index] = lastMarketId;
            _markets[lastMarketId].index = marketData.index;
            marketIds.pop();
            marketData.index = 0;
        } else if (oldNetCredit == 0 && newNetCredit > 0) {
            require(marketIds.length < MAX_MARKETS, TooManyMarkets());
            marketData.maturity = market.maturity.toUint48();
            // forge-lint: disable-next-item(unsafe-typecast) marketIds.length < MAX_MARKETS.
            marketData.index = uint8(marketIds.length);
            marketIds.push(marketId);
        }
        emit UpdateMarket(marketId, marketData.netCredit, marketData.assets);
        // forge-lint: disable-next-item(unsafe-typecast) both net credit values fit in uint128.
        change = int256(uint256(newNetCredit)) - int256(oldNetCredit);
    }

    /// @dev Returns the number of durations in packedDurations that are at most the time to maturity.
    function durationCount(uint256 maturity) internal view returns (uint256 count) {
        uint256 timeToMaturity = maturity.zeroFloorSub(block.timestamp);
        while (count < durationsLength && timeToMaturity >= packedDurations.get(count)) count++;
    }

    /// @dev Liquidation cursors are omitted from collateral ids.
    function ids(Market memory market) public view returns (bytes32[] memory) {
        uint256 durationsCount = _maturities[market.maturity].durationCount;

        bytes32[] memory idsArray = new bytes32[](1 + market.collateralParams.length * 2 + durationsCount);

        uint256 j;
        idsArray[j++] = adapterId;
        for (uint256 i = 0; i < market.collateralParams.length; i++) {
            address collateralToken = market.collateralParams[i].token;
            idsArray[j++] = keccak256(abi.encode("collateralToken", collateralToken));
            idsArray[j++] = keccak256(
                abi.encode(
                    "collateral", collateralToken, market.collateralParams[i].oracle, market.collateralParams[i].lltv
                )
            );
        }
        for (uint256 i = 0; i < durationsCount; i++) {
            idsArray[j++] = keccak256(abi.encode("duration", packedDurations.get(i)));
        }

        return idsArray;
    }
}
