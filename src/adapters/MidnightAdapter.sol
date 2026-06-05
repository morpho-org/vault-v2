// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Morpho Association
pragma solidity 0.8.34;

import {IMidnight, Offer, Market} from "lib/midnight/src/interfaces/IMidnight.sol";
import {Signature, EIP712_DOMAIN_TYPEHASH} from "lib/midnight/src/ratifiers/interfaces/IEcrecoverRatifier.sol";
import {CALLBACK_SUCCESS} from "lib/midnight/src/libraries/ConstantsLib.sol";
import {IdLib} from "lib/midnight/src/libraries/IdLib.sol";
import {HashLib} from "lib/midnight/src/ratifiers/libraries/HashLib.sol";
import {IERC20} from "../interfaces/IERC20.sol";
import {SafeERC20Lib} from "../libraries/SafeERC20Lib.sol";
import {MathLib} from "../libraries/MathLib.sol";
import {IVaultV2} from "../interfaces/IVaultV2.sol";
import {IMidnightAdapter, MaturityData, MarketData, IAdapter} from "./interfaces/IMidnightAdapter.sol";
import {DurationsLib} from "./libraries/DurationsLib.sol";

/// @dev Approximates held assets by linearly accounting for interest per market, aggregated by maturity.
/// @dev Losses are immediately accounted minus a discount applied to the remaining interest to be earned, in proportion
/// to the relative sizes of the loss and the adapter's position in the market hit by the loss.
/// @dev The adapter must have the allocator role in its parent vault to be able to buy & sell on markets.
contract MidnightAdapter is IMidnightAdapter {
    using MathLib for uint256;
    using MathLib for uint128;
    using MathLib for int256;
    using DurationsLib for bytes32;

    /* IMMUTABLES */

    address public immutable asset;
    address public immutable parentVault;
    address public immutable midnight;
    bytes32 public immutable adapterId;
    /// @dev Sorted durations that can be used to cap the time to maturity.
    /// @dev Sorted in ascending order.
    bytes32 public immutable packedDurations;
    uint256 public immutable durationsLength;

    /* MANAGEMENT */

    address public skimRecipient;

    /* ACCOUNTING */

    uint128 public totalAssets;
    uint128 public currentGrowth;
    uint48 public lastUpdate;
    /// @dev Maximum steps of an accrual.
    /// @dev A maturity uses an availability slot iff it has some units and is > now after accrual.
    uint8 public constant MAX_PENDING_MATURITIES = 50;
    uint8 public availableMaturities = MAX_PENDING_MATURITIES;
    mapping(uint256 timestamp => MaturityData) public _maturities;
    mapping(bytes32 marketId => MarketData) public _markets;
    mapping(bytes32 marketId => mapping(address user => uint256)) public shares;
    /* CONSTRUCTOR */

    constructor(address _parentVault, address _midnight, uint256[] memory _durations) {
        asset = IVaultV2(_parentVault).asset();
        parentVault = _parentVault;
        midnight = _midnight;
        lastUpdate = block.timestamp.toUint48();
        SafeERC20Lib.safeApprove(asset, _midnight, type(uint256).max);
        SafeERC20Lib.safeApprove(asset, _parentVault, type(uint256).max);
        adapterId = keccak256(abi.encode("this", address(this)));

        packedDurations = DurationsLib.pack(_durations);
        durationsLength = _durations.length;
    }

    /* GETTERS */

    function maturities(uint256 date) public view returns (MaturityData memory) {
        return _maturities[date];
    }

    /// @dev Returns the growth of the market. Can be stale after maturity.
    function markets(bytes32 marketId) public view returns (MarketData memory) {
        return _markets[marketId];
    }

    function durations() public view returns (uint256[] memory) {
        uint256[] memory _durations = new uint256[](durationsLength);
        for (uint256 i = 0; i < durationsLength; i++) {
            _durations[i] = packedDurations.get(i);
        }
        return _durations;
    }

    /* SKIM FUNCTIONS */

    function setSkimRecipient(address newSkimRecipient) external {
        require(msg.sender == IVaultV2(parentVault).owner(), NotAuthorized());
        skimRecipient = newSkimRecipient;
        emit SetSkimRecipient(newSkimRecipient);
    }

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
        require(IVaultV2(parentVault).isAllocator(msg.sender), NotAuthorized());
        bytes32 marketId = IdLib.toId(market, block.chainid, midnight);
        MarketData storage marketData = _markets[marketId];
        uint256 oldAdapterNetCredit = currentNetCredit(marketId);
        IMidnight(midnight).withdraw(market, withdrawnAssets, address(this), address(this));
        uint256 currentAdapterNetCredit = currentNetCredit(marketId);
        uint256 withdrawNetCreditDecrease = oldAdapterNetCredit - currentAdapterNetCredit;
        uint256 oldVaultNetCredit = marketData.vaultNetCredit;

        accrueInterest();
        updateDurationCountAndAllocations(market);
        realizeLoss(marketData, marketId, market.maturity, -int256(withdrawNetCreditDecrease));
        removeNetCredit(marketId, market.maturity, withdrawNetCreditDecrease);

        uint256 vaultNetCreditDecrease = oldVaultNetCredit - marketData.vaultNetCredit;
        IVaultV2(parentVault)
            .deallocate(address(this), abi.encode(ids(market), -vaultNetCreditDecrease.toInt256()), withdrawnAssets);
        emit WithdrawToVault(marketId, withdrawnAssets, vaultNetCreditDecrease);
    }

    /// @dev To withdraw early, users can sell on midnight and in a callback immediately repay & withdraw here.
    function withdrawShares(Market memory market, uint256 redeemedShares) external {
        bytes32 marketId = IdLib.toId(market, block.chainid, midnight);
        MarketData storage marketData = _markets[marketId];
        uint256 oldVaultNetCredit = marketData.vaultNetCredit;

        accrueInterest();
        updateDurationCountAndAllocations(market);
        realizeLoss(marketData, marketId, market.maturity, 0);

        if (marketData.vaultNetCredit != oldVaultNetCredit) {
            uint256 vaultNetCreditDecrease = oldVaultNetCredit - marketData.vaultNetCredit;
            IVaultV2(parentVault)
                .deallocate(address(this), abi.encode(ids(market), -vaultNetCreditDecrease.toInt256()), 0);
        }

        uint256 withdrawnAssets = redeemedShares.mulDivDown(marketData.userNetCredit + 1, marketData.userShares + 1);

        uint256 oldAdapterNetCredit = currentNetCredit(marketId);
        IMidnight(midnight).withdraw(market, withdrawnAssets, address(this), msg.sender);

        uint256 currentAdapterNetCredit = currentNetCredit(marketId);
        uint256 withdrawNetCreditDecrease = oldAdapterNetCredit - currentAdapterNetCredit;
        marketData.userNetCredit -= uint128(withdrawNetCreditDecrease);
        marketData.userShares -= redeemedShares.toUint128();
        shares[marketId][msg.sender] -= redeemedShares;
    }

    function updateDurationCountAndAllocations(Market memory market) public {
        MaturityData storage maturityData = _maturities[market.maturity];
        uint256 oldDurationCount = maturityData.durationCount;
        uint256 newDurationCount = durationCount(market.maturity);
        maturityData.durationCount = uint8(newDurationCount);
        emit UpdateDurationCountAndAllocations(market.maturity, newDurationCount, maturityData.vaultNetCredit);
        // VaultV2.deallocate requires allocation > 0 for each returned id.
        if (newDurationCount < oldDurationCount && maturityData.vaultNetCredit > 0) {
            bytes32[] memory zeroedDurationsIds = new bytes32[](oldDurationCount - newDurationCount);
            for (uint256 i = 0; i < zeroedDurationsIds.length; i++) {
                zeroedDurationsIds[i] = keccak256(abi.encode("duration", packedDurations.get(newDurationCount + i)));
            }
            IVaultV2(parentVault)
                .deallocate(
                    address(this), abi.encode(zeroedDurationsIds, -int256(uint256(maturityData.vaultNetCredit))), 0
                );
        }
    }

    /* ACCRUAL */

    function accrueInterestView() public view returns (uint48, uint128, uint128, uint256) {
        uint48 _firstMaturity = _maturities[0].nextMaturity;
        uint128 newGrowth = currentGrowth;
        uint256 removedMaturities = 0;
        uint256 gainedAssets = 0;
        uint256 accrueFrom = lastUpdate;

        while (_firstMaturity != 0 && _firstMaturity <= block.timestamp) {
            gainedAssets += uint256(newGrowth) * (_firstMaturity - accrueFrom);
            newGrowth -= _maturities[_firstMaturity].growth;
            accrueFrom = _firstMaturity;
            _firstMaturity = _maturities[_firstMaturity].nextMaturity;
            removedMaturities++;
        }

        gainedAssets += uint256(newGrowth) * (block.timestamp - accrueFrom);

        return (_firstMaturity, newGrowth, (totalAssets + gainedAssets).toUint128(), removedMaturities);
    }

    function accrueInterest() public returns (uint48, uint128, uint256) {
        if (lastUpdate != block.timestamp) {
            uint48 newHead;
            uint256 removedMaturities;
            (newHead, currentGrowth, totalAssets, removedMaturities) = accrueInterestView();
            availableMaturities += uint8(removedMaturities);
            _maturities[0].nextMaturity = newHead;
            _maturities[newHead].prevMaturity = 0;
            lastUpdate = block.timestamp.toUint48();
            emit AccrueInterest(currentGrowth, totalAssets);
        }
        return (_maturities[0].nextMaturity, currentGrowth, totalAssets);
    }

    /// @dev Returns an estimate of the real assets assigned to the adapter.
    /// @dev Excludes assets reserved for users.
    function realAssets() external view returns (uint256) {
        (,, uint256 newTotalAssets,) = accrueInterestView();
        return newTotalAssets;
    }

    /* ALLOCATION FUNCTIONS */

    /// @dev Can be called by this adapter from a buy callback.
    function allocate(bytes memory data, uint256, bytes4, address caller)
        external
        view
        returns (bytes32[] memory, int256)
    {
        require(caller == address(this), SelfAllocationOnly());
        // Return exactly the data passed to the function.
        assembly ("memory-safe") {
            return(add(data, 32), mload(data))
        }
    }

    /// @dev Can be called by this adapter from a sell callback, a withdraw, or a loss realization.
    /// @dev Can be called by a user through forceDeallocate.
    /// @dev A force deallocator forfeits all his share of the pending continuous fee.
    function deallocate(bytes memory data, uint256 deallocatedAmount, bytes4 messageSig, address caller)
        external
        returns (bytes32[] memory, int256)
    {
        require(msg.sender == parentVault, NotAuthorized());
        if (messageSig == IVaultV2.forceDeallocate.selector) {
            Market memory market = abi.decode(data, (Market));
            bytes32 marketId = IdLib.toId(market, block.chainid, midnight);
            MarketData storage marketData = _markets[marketId];
            uint256 oldVaultNetCredit = marketData.vaultNetCredit;

            accrueInterest();
            updateDurationCountAndAllocations(market);
            IMidnight(midnight).updatePosition(market, address(this));
            realizeLoss(marketData, marketId, market.maturity, 0);

            uint256 mintedShares =
                deallocatedAmount.mulDivDown(uint256(marketData.userShares) + 1, uint256(marketData.userNetCredit) + 1);
            shares[marketId][caller] += mintedShares;
            marketData.userShares += uint128(mintedShares);
            marketData.userNetCredit += uint128(deallocatedAmount);
            removeNetCredit(marketId, market.maturity, deallocatedAmount);

            uint256 vaultNetCreditDecrease = oldVaultNetCredit - marketData.vaultNetCredit;
            emit ForceDeallocate(marketId, deallocatedAmount, vaultNetCreditDecrease);
            return (ids(market), -vaultNetCreditDecrease.toInt256());
        } else {
            require(caller == address(this), SelfAllocationOnly());
            // Return exactly the data passed to the function.
            assembly ("memory-safe") {
                return(add(data, 32), mload(data))
            }
        }
    }

    /* MIDNIGHT CALLBACKS */

    function isRatified(Offer memory offer, bytes memory data) external view returns (bytes32) {
        // Collaterals will be checked through vault ids.
        require(offer.market.loanToken == asset, LoanAssetMismatch());
        require(offer.maker == address(this), IncorrectOwner());
        require(offer.callback == address(this), IncorrectCallbackAddress());
        require(offer.start <= block.timestamp, IncorrectStart());
        require(offer.buy || offer.reduceOnly, NoDebtCreation());

        (Signature memory sig, bytes32 root, uint256 leafIndex, bytes32[] memory proof) =
            abi.decode(data, (Signature, bytes32, uint256, bytes32[]));
        require(HashLib.isLeaf(root, HashLib.hashOffer(offer), leafIndex, proof), InvalidProof());
        bytes32 structHash = keccak256(abi.encode(HashLib.offerTreeTypeHash(proof.length), root));
        bytes32 domainSeparator = keccak256(abi.encode(EIP712_DOMAIN_TYPEHASH, block.chainid, address(this)));
        bytes32 digest = keccak256(bytes.concat("\x19\x01", domainSeparator, structHash));
        address signer = ecrecover(digest, sig.v, sig.r, sig.s);
        require(signer != address(0), IncorrectSigner());
        require(IVaultV2(parentVault).isAllocator(signer), IncorrectSigner());

        return CALLBACK_SUCCESS;
    }

    function onBuy(
        bytes32 marketId,
        Market memory market,
        uint256 paidAssets,
        uint256 boughtCredit,
        uint256 buyPendingFeeIncrease,
        address buyer,
        bytes memory
    ) external returns (bytes32) {
        MaturityData storage maturityData = _maturities[market.maturity];
        MarketData storage marketData = _markets[marketId];
        uint256 timeToMaturity = market.maturity.zeroFloorSub(block.timestamp);
        uint256 boughtNetCredit = boughtCredit - buyPendingFeeIncrease;
        uint256 oldVaultNetCredit = marketData.vaultNetCredit;

        require(msg.sender == midnight, NotMidnight());
        require(buyer == address(this), NotSelf());
        require(boughtNetCredit >= paidAssets, BuyAtLoss());

        accrueInterest();
        updateDurationCountAndAllocations(market);
        realizeLoss(marketData, marketId, market.maturity, int256(boughtNetCredit));

        if (timeToMaturity > 0) {
            uint256 interest = boughtNetCredit - paidAssets;
            uint128 growthIncrease = (interest / timeToMaturity).toUint128();
            totalAssets += (paidAssets + interest % timeToMaturity).toUint128();
            marketData.growth += growthIncrease;
            maturityData.growth += growthIncrease;
            currentGrowth += growthIncrease;
        } else {
            totalAssets += boughtNetCredit.toUint128();
        }

        maturityData.vaultNetCredit += boughtNetCredit.toUint128();
        marketData.vaultNetCredit += boughtNetCredit.toUint128();

        int256 netCreditChange = int256(uint256(marketData.vaultNetCredit)) - int256(oldVaultNetCredit);
        IVaultV2(parentVault).allocate(address(this), abi.encode(ids(market), netCreditChange), paidAssets);

        // Insert the maturity in the list if needed
        if (maturityData.vaultNetCredit == boughtNetCredit && boughtNetCredit > 0 && market.maturity > block.timestamp)
        {
            availableMaturities--;
            uint48 prevMaturity = 0;
            uint48 nextMaturity = _maturities[0].nextMaturity;
            while (nextMaturity != 0 && nextMaturity < market.maturity) {
                prevMaturity = nextMaturity;
                nextMaturity = _maturities[prevMaturity].nextMaturity;
            }
            maturityData.nextMaturity = _maturities[prevMaturity].nextMaturity;
            maturityData.prevMaturity = prevMaturity;
            _maturities[prevMaturity].nextMaturity = market.maturity.toUint48();
            _maturities[maturityData.nextMaturity].prevMaturity = market.maturity.toUint48();
            emit InsertMaturity(market.maturity);
        }

        emit Buy(marketId, paidAssets, boughtNetCredit, netCreditChange);
        return CALLBACK_SUCCESS;
    }

    function onSell(
        bytes32 marketId,
        Market memory market,
        uint256 sellerAssets,
        uint256 units,
        uint256 sellPendingFeeDecrease,
        address seller,
        address,
        bytes memory
    ) external returns (bytes32) {
        uint256 vaultTotalAssetsBefore = IVaultV2(parentVault).totalAssets();
        MarketData storage marketData = _markets[marketId];
        uint256 sellNetCreditDecrease = units - sellPendingFeeDecrease;
        uint256 oldVaultNetCredit = marketData.vaultNetCredit;

        require(msg.sender == midnight, NotMidnight());
        require(seller == address(this), NotSelf());

        accrueInterest();
        updateDurationCountAndAllocations(market);
        realizeLoss(marketData, marketId, market.maturity, -int256(sellNetCreditDecrease));

        removeNetCredit(marketId, market.maturity, sellNetCreditDecrease);

        uint256 vaultNetCreditDecrease = oldVaultNetCredit - marketData.vaultNetCredit;
        IVaultV2(parentVault)
            .deallocate(address(this), abi.encode(ids(market), -vaultNetCreditDecrease.toInt256()), sellerAssets);

        uint256 vaultRealAssetsAfter = IERC20(asset).balanceOf(address(parentVault));
        uint256 adaptersLength = IVaultV2(parentVault).adaptersLength();
        for (uint256 i = 0; i < adaptersLength; i++) {
            vaultRealAssetsAfter += IAdapter(IVaultV2(parentVault).adapters(i)).realAssets();
        }
        require(vaultRealAssetsAfter >= vaultTotalAssetsBefore, BufferTooLow());

        emit Sell(marketId, sellerAssets, oldVaultNetCredit - marketData.vaultNetCredit);
        return CALLBACK_SUCCESS;
    }

    /* INTERNAL FUNCTIONS */

    function currentNetCredit(bytes32 marketId) internal view returns (uint256) {
        return
            IMidnight(midnight).creditOf(marketId, address(this))
                - IMidnight(midnight).pendingFee(marketId, address(this));
    }

    /// @dev Realizes any loss between the expected and actual net credit.
    /// @dev Splits the loss between users and vault, and updates vault accounting.
    function realizeLoss(
        MarketData storage marketData,
        bytes32 marketId,
        uint256 maturity,
        int256 expectedAdapterNetCreditDelta
    ) internal {
        uint256 currentAdapterNetCredit = currentNetCredit(marketId);
        uint256 oldAdapterNetCredit = marketData.vaultNetCredit + marketData.userNetCredit;
        uint256 expectedAdapterNetCredit = (int256(oldAdapterNetCredit) + expectedAdapterNetCreditDelta).toUint256();
        if (expectedAdapterNetCredit > currentAdapterNetCredit) {
            uint256 loss = expectedAdapterNetCredit - currentAdapterNetCredit;
            uint256 userLoss =
                oldAdapterNetCredit == 0 ? 0 : uint256(marketData.userNetCredit).mulDivUp(loss, oldAdapterNetCredit);
            uint256 vaultLoss = loss - userLoss;
            marketData.userNetCredit -= uint128(userLoss);
            if (vaultLoss > 0) removeNetCredit(marketId, maturity, vaultLoss);
        }
    }

    /// @dev Removes netCredit proportionally from current accounted assets and future growth.
    function removeNetCredit(bytes32 marketId, uint256 maturity, uint256 removedNetCredit) internal {
        if (removedNetCredit == 0) return;

        MaturityData storage maturityData = _maturities[maturity];
        MarketData storage marketData = _markets[marketId];

        if (maturity > block.timestamp) {
            uint256 timeToMaturity = maturity - block.timestamp;
            uint128 growthDecrease = marketData.growth.mulDivUp(removedNetCredit, marketData.vaultNetCredit).toUint128();
            marketData.growth -= growthDecrease;
            maturityData.growth -= growthDecrease;
            currentGrowth -= growthDecrease;
            totalAssets = (totalAssets + (growthDecrease * timeToMaturity) - removedNetCredit).toUint128();
        } else {
            totalAssets -= removedNetCredit.toUint128();
        }
        maturityData.vaultNetCredit -= removedNetCredit.toUint128();
        marketData.vaultNetCredit -= removedNetCredit.toUint128();

        if (removedNetCredit > 0 && maturityData.vaultNetCredit == 0 && maturity > block.timestamp) {
            availableMaturities++;
            _maturities[maturityData.prevMaturity].nextMaturity = maturityData.nextMaturity;
            _maturities[maturityData.nextMaturity].prevMaturity = maturityData.prevMaturity;
            emit RemoveMaturity(maturity);
        }
    }

    /// @dev Returns the number of durations in packedDurations that are most the time to maturity.
    function durationCount(uint256 maturity) internal view returns (uint256 count) {
        uint256 timeToMaturity = maturity.zeroFloorSub(block.timestamp);
        while (count < durationsLength && timeToMaturity >= packedDurations.get(count)) count++;
    }

    function ids(Market memory market) public view returns (bytes32[] memory) {
        uint256 durationsCount = durationCount(market.maturity);

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

    /* UNUSED CALLBACKS */
}
