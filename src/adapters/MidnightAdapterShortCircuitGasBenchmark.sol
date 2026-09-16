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
import {WAD} from "../libraries/ConstantsLib.sol";
import {IVaultV2} from "../interfaces/IVaultV2.sol";
import {ITimelock, Operation, TimelockStatus} from "../interfaces/ITimelock.sol";
import {IMidnightAdapter, MaturityData, IAdapter} from "./interfaces/IMidnightAdapter.sol";
import {DurationsLib} from "./libraries/DurationsLib.sol";

struct MarketData {
    uint128 netCredit;
    uint128 lossFactor;
    uint128 assets;
    uint48 maturity;
    uint48 lastUpdate;
    uint8 index;
}

/// @dev Approximates held assets by linearly accounting for interest per market.
/// @dev Losses are immediately accounted in realAssets() minus a discount applied to the remaining interest to be
/// earned, in proportion to the relative sizes of the loss and the adapter's position in the market hit by the loss.
/// @dev The adapter must have the allocator role in its parent vault to buy, and the allocator or sentinel role to
/// make sell offers, to withdraw to the vault and to update duration caps.
/// @dev Buy offers must set callbackData to abi.encode(adapter, data) to select where the liquidity will be
/// deallocated, or to "" to take the liquidity in the vault's idle funds.
/// @dev For self-funding, data is abi.encode(fundingMarket).
/// @dev Before adding the adapter to the vault, its timelocks must be properly set.
///
/// TIMELOCKS
/// @dev Uses a shared Timelock through timelockOperation. Authorization is read from the parent vault on every call.
contract MidnightAdapterShortCircuitGasBenchmark is IMidnightAdapter {
    using MathLib for uint256;
    using DurationsLib for bytes32;

    /* IMMUTABLES */

    address public immutable asset;
    address public immutable parentVault;
    address public immutable midnight;
    address public immutable timelock;
    bytes32 public immutable adapterId;
    /// @dev Durations that can be used to cap the time to maturity.
    /// @dev Sorted in ascending order.
    bytes32 public immutable packedDurations;
    uint256 public immutable durationsLength;

    /* MANAGEMENT */

    address public skimRecipient;
    bool public skipBufferCheck;
    /// @dev Minimum net simple interest rate per second, WAD-scaled, enforced on maker and taker buys before maturity.
    uint256 public minRate;
    mapping(address subRatifier => bool) public isSubRatifier;

    /* ACCOUNTING */

    /// @dev Takers of offers of the adapter can fill slots with dust takes.
    uint8 public constant MAX_MARKETS = 250;

    bytes32[] public marketIds;
    /// @dev Net credit last reported to the vault's caps.
    mapping(bytes32 marketId => MarketData) internal _markets;
    mapping(uint256 timestamp => MaturityData) internal _maturities;
    bytes32 transient overridenMarketId;
    uint256 transient overridenMarketNetCredit;
    /* CONSTRUCTOR */

    constructor(address _parentVault, address _midnight, address _timelock, uint256[] memory _durations) {
        asset = IVaultV2(_parentVault).asset();
        parentVault = _parentVault;
        midnight = _midnight;
        timelock = _timelock;
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
        require(!IMidnight(midnight).liquidationLocked(IdLib.toId(offer.market), address(this)), SellInProgress());
        // Collaterals and durations will be checked through vault ids.
        require(offer.market.loanToken == asset, LoanAssetMismatch());
        require(offer.maker == address(this), IncorrectMaker());
        require(offer.callback == address(this), IncorrectCallbackAddress());
        // For buy offers, Midnight enforces receiverIfMakerIsSeller == address(0).
        require(offer.buy || offer.receiverIfMakerIsSeller == address(this), IncorrectReceiver());

        (address subRatifier, bytes memory subData) = abi.decode(data, (address, bytes));
        require(isSubRatifier[subRatifier], SubRatifierUnauthorized());
        return IRatifier(subRatifier).isRatified(offer, subData, taker);
    }

    /* TIMELOCKS FUNCTIONS */

    function timelockOperation(Operation op, bytes calldata data) external {
        if (op == Operation.Submit) {
            require(msg.sender == IVaultV2(parentVault).curator(), NotAuthorized());
        } else if (op == Operation.Revoke) {
            require(
                msg.sender == IVaultV2(parentVault).curator() || IVaultV2(parentVault).isSentinel(msg.sender),
                NotAuthorized()
            );
        } else {
            timelocked();
        }
        ITimelock(timelock).operation(op, data);
    }

    function timelockStatus(bytes calldata data) external view returns (TimelockStatus memory) {
        return ITimelock(timelock).status(address(this), data);
    }

    function timelocked() internal {
        ITimelock(timelock).useTimelock(msg.data);
    }

    /* CURATOR FUNCTIONS */

    function setSkipBufferCheck(bool newSkipBufferCheck) external {
        timelocked();
        skipBufferCheck = newSkipBufferCheck;
        emit SetSkipBufferCheck(newSkipBufferCheck);
    }

    function setMinRate(uint256 newMinRate) external {
        timelocked();
        minRate = newMinRate;
        emit SetMinRate(newMinRate);
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

        require(!IMidnight(midnight).liquidationLocked(marketId, address(this)), SellInProgress());

        // forge-lint: disable-next-item(reentrancy-no-eth) withdraw does not call back.
        IMidnight(midnight).withdraw(market, withdrawnAssets, address(this), address(this));
        int256 change = updateMarket(marketId, market, 0, 0);

        // forge-lint: disable-next-item(reentrancy-no-eth) deallocate in this adapter does not make calls here
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
        // updatePositionView only reads market.maturity.
        Market memory dummyMarket;
        for (uint256 i = 0; i < length; i++) {
            bytes32 marketId = marketIds[i];
            MarketData memory marketData = _markets[marketId];
            uint256 newNetCredit;
            if (marketId == overridenMarketId) {
                newNetCredit = overridenMarketNetCredit;
            } else {
                require(!IMidnight(midnight).liquidationLocked(marketId, address(this)), SellInProgress());
                if (marketData.lossFactor == IMidnight(midnight).lossFactor(marketId)) {
                    newNetCredit = marketData.netCredit;
                } else {
                    dummyMarket.maturity = marketData.maturity;
                    newNetCredit = currentNetCredit(marketId, dummyMarket);
                }
            }
            assets += newNetCredit - futureInterest(marketData, newNetCredit);
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

            bytes32 marketId = IdLib.toId(offer.market);
            require(!IMidnight(midnight).liquidationLocked(marketId, address(this)), SellInProgress());
            IVaultV2(parentVault).accrueInterest();

            // Skip onSell since we are already in a deallocate call.
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
        uint256 boughtNetCredit = boughtCredit - buyPendingFeeIncrease;
        require(boughtNetCredit >= paidAssets, BuyAtLoss());

        // Cache corrected net credit before call to allocate
        (overridenMarketId, overridenMarketNetCredit) = (marketId, currentNetCredit(marketId, market) - boughtNetCredit);
        IVaultV2(parentVault).accrueInterest();
        (overridenMarketId, overridenMarketNetCredit) = (bytes32(0), 0);

        MaturityData storage maturityData = _maturities[market.maturity];
        // forge-lint: disable-next-item(unsafe-typecast) durationCount <= MAX_DURATIONS.
        if (maturityData.netCredit == 0) maturityData.durationCount = uint8(durationCount(market.maturity));
        int256 change = updateMarket(marketId, market, boughtNetCredit, paidAssets);
        uint256 idleAssets = IERC20(asset).balanceOf(parentVault);
        if (callbackData.length > 0 && paidAssets > idleAssets) {
            (address fundingAdapter, bytes memory fundingData) = abi.decode(callbackData, (address, bytes));
            if (fundingAdapter == address(this)) {
                this.withdrawToVault(abi.decode(fundingData, (Market)), paidAssets - idleAssets);
            } else {
                // forge-lint: disable-next-item(reentrancy-no-eth) the adapter is trusted.
                IVaultV2(parentVault).deallocate(fundingAdapter, fundingData, paidAssets - idleAssets);
            }
        }

        // forge-lint: disable-next-item(reentrancy-no-eth) reentry is expected.
        IVaultV2(parentVault).allocate(address(this), abi.encode(ids(market), change), paidAssets);

        uint256 timeToMaturity = market.maturity.zeroFloorSub(block.timestamp);
        require(
            timeToMaturity == 0 || paidAssets == 0
                || (boughtNetCredit - paidAssets).mulDivDown(WAD, paidAssets) / timeToMaturity >= minRate,
            RateTooLow()
        );

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

        int256 change;
        if (skipBufferCheck) {
            change = updateMarket(marketId, market, 0, 0);
            IVaultV2(parentVault).deallocate(address(this), abi.encode(ids(market), change), sellerAssets);
        } else {
            (overridenMarketId, overridenMarketNetCredit) =
            (marketId, currentNetCredit(marketId, market) + soldCredit - sellPendingFeeDecrease);
            uint256 vaultTotalAssetsBefore = IVaultV2(parentVault).totalAssets();
            (overridenMarketId, overridenMarketNetCredit) = (bytes32(0), 0);

            change = updateMarket(marketId, market, 0, 0);
            IVaultV2(parentVault).deallocate(address(this), abi.encode(ids(market), change), sellerAssets);

            (overridenMarketId, overridenMarketNetCredit) = (marketId, _markets[marketId].netCredit);
            uint256 vaultRealAssetsAfter = IERC20(asset).balanceOf(parentVault);
            uint256 adaptersLength = IVaultV2(parentVault).adaptersLength();
            for (uint256 i = 0; i < adaptersLength; i++) {
                vaultRealAssetsAfter += IAdapter(IVaultV2(parentVault).adapters(i)).realAssets();
            }
            (overridenMarketId, overridenMarketNetCredit) = (bytes32(0), 0);
            require(vaultRealAssetsAfter >= vaultTotalAssetsBefore, BufferTooLow());
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

    /// @dev Returns the remaining interest attributable to credit in the market.
    function futureInterest(MarketData memory marketData, uint256 credit) internal view returns (uint256) {
        if (marketData.netCredit == 0 || block.timestamp >= marketData.maturity) return 0;
        uint256 interest = (uint256(marketData.netCredit) - marketData.assets)
        .mulDivUp(marketData.maturity - block.timestamp, marketData.maturity - marketData.lastUpdate);
        return interest.mulDivUp(credit, marketData.netCredit);
    }

    /// @dev Returns the change in net credit reported to the vault's caps.
    function updateMarket(bytes32 marketId, Market memory market, uint256 boughtNetCredit, uint256 paidAssets)
        internal
        returns (int256 change)
    {
        MarketData storage marketData = _markets[marketId];
        uint256 oldNetCredit = marketData.netCredit;
        uint128 newNetCredit = currentNetCredit(marketId, market);
        marketData.lossFactor = IMidnight(midnight).lossFactor(marketId);
        uint256 newFutureInterest = block.timestamp >= market.maturity
            ? 0
            : futureInterest(marketData, newNetCredit - boughtNetCredit) + boughtNetCredit - paidAssets;
        // forge-lint: disable-next-item(unsafe-typecast) assets <= newNetCredit <= type(uint128).max.
        marketData.assets = uint128(newNetCredit - newFutureInterest);
        marketData.netCredit = newNetCredit;
        marketData.lastUpdate = block.timestamp.toUint48();
        _maturities[market.maturity].netCredit =
            (uint256(_maturities[market.maturity].netCredit) + newNetCredit - oldNetCredit).toUint128();
        if (newNetCredit == 0 && oldNetCredit > 0) {
            bytes32 lastMarketId = marketIds[marketIds.length - 1];
            marketIds[marketData.index] = lastMarketId;
            _markets[lastMarketId].index = marketData.index;
            marketIds.pop();
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

    function ids(Market memory market) public view returns (bytes32[] memory) {
        uint256 durationsCount = _maturities[market.maturity].durationCount;

        bytes32[] memory idsArray = new bytes32[](1 + market.collateralParams.length * 2 + durationsCount);

        uint256 j;
        idsArray[j++] = adapterId;
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
