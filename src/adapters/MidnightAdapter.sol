// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Morpho Association
pragma solidity 0.8.34;

import {IMidnight, Offer, Market} from "lib/midnight/src/interfaces/IMidnight.sol";
import {MAX_TICK} from "lib/midnight/src/libraries/TickLib.sol";
import {Signature, EIP712_DOMAIN_TYPEHASH} from "lib/midnight/src/ratifiers/interfaces/IEcrecoverRatifier.sol";
import {CALLBACK_SUCCESS} from "lib/midnight/src/libraries/ConstantsLib.sol";
import {TakeAmountsLib} from "lib/midnight/src/periphery/TakeAmountsLib.sol";
import {IdLib} from "lib/midnight/src/libraries/IdLib.sol";
import {HashLib} from "lib/midnight/src/ratifiers/libraries/HashLib.sol";
import {IERC20} from "../interfaces/IERC20.sol";
import {SafeERC20Lib} from "../libraries/SafeERC20Lib.sol";
import {MathLib} from "../libraries/MathLib.sol";
import {IVaultV2} from "../interfaces/IVaultV2.sol";
import {IMidnightAdapter, MaturityData, IAdapter} from "./interfaces/IMidnightAdapter.sol";
import {DurationsLib} from "./libraries/DurationsLib.sol";

/// @dev Approximates held assets by linearly accounting for interest separately for each market.
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

    uint8 public constant MAX_PENDING_MATURITIES = 50;

    uint128 public totalAssets;
    uint128 public currentGrowth;
    uint48 public lastUpdate;
    uint8 public pendingMaturitiesLength;
    /// @dev Used to avoid reading the entire pendingMaturities array most of the time.
    uint48 public nextMaturityFloor = type(uint48).max;
    /// @dev Unordered array of future maturities where the adapter has credit.
    /// @dev Elements at index >= pendingMaturitiesLength should be ignored.
    uint48[MAX_PENDING_MATURITIES] public pendingMaturities;
    mapping(uint256 timestamp => MaturityData) public _maturities;
    mapping(bytes32 marketId => uint256) public netCredit;
    /* CONSTRUCTOR */

    constructor(address _parentVault, address _midnight, uint256[] memory _durations) {
        asset = IVaultV2(_parentVault).asset();
        parentVault = _parentVault;
        midnight = _midnight;
        lastUpdate = uint48(block.timestamp);
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
        IMidnight(midnight).withdraw(market, withdrawnAssets, address(this), address(this));
        uint256 newNetCredit = IMidnight(midnight).creditOf(marketId, address(this))
            - IMidnight(midnight).pendingFee(marketId, address(this));
        // new net credit cannot be > old credit
        uint256 totalNetCreditDecrease = netCredit[marketId] - newNetCredit;

        accrueInterest();
        updateDurationCountAndAllocations(market);

        if (totalNetCreditDecrease > 0) {
            removeUnits(marketId, market.maturity, totalNetCreditDecrease);
        }

        IVaultV2(parentVault)
            .deallocate(address(this), abi.encode(ids(market), -totalNetCreditDecrease.toInt256()), withdrawnAssets);
        emit WithdrawToVault(marketId, withdrawnAssets, totalNetCreditDecrease);
    }

    function updateDurationCountAndAllocations(Market memory market) public {
        MaturityData storage maturityData = _maturities[market.maturity];
        uint256 oldDurationCount = maturityData.durationCount;
        uint256 newDurationCount = durationCount(market.maturity);
        maturityData.durationCount = uint8(newDurationCount);
        emit UpdateDurationCountAndAllocations(market.maturity, newDurationCount, maturityData.netCredit);
        // VaultV2.deallocate requires allocation > 0 for each returned id.
        if (newDurationCount < oldDurationCount && maturityData.netCredit > 0) {
            bytes32[] memory zeroedDurationsIds = new bytes32[](oldDurationCount - newDurationCount);
            for (uint256 i = 0; i < zeroedDurationsIds.length; i++) {
                zeroedDurationsIds[i] = keccak256(abi.encode("duration", packedDurations.get(newDurationCount + i)));
            }
            IVaultV2(parentVault)
                .deallocate(address(this), abi.encode(zeroedDurationsIds, -int256(uint256(maturityData.netCredit))), 0);
        }
    }

    /* ACCRUAL */

    function accrueInterestView() public view returns (uint128, uint256) {
        uint128 newGrowth = currentGrowth;
        uint256 newTotalAssets = totalAssets;

        if (block.timestamp >= nextMaturityFloor) {
            for (uint256 i = pendingMaturitiesLength; i > 0; i--) {
                uint48 maturity = pendingMaturities[i - 1];
                if (maturity <= block.timestamp) {
                    newTotalAssets += uint256(_maturities[maturity].growth) * (maturity - lastUpdate);
                    newGrowth -= _maturities[maturity].growth;
                }
            }
        }
        newTotalAssets += uint256(newGrowth) * (block.timestamp - lastUpdate);

        return (newGrowth, newTotalAssets);
    }

    function accrueInterest() public returns (uint128, uint256) {
        uint128 newGrowth = currentGrowth;
        uint256 newTotalAssets = totalAssets;

        if (block.timestamp >= nextMaturityFloor) {
            uint48 newMin = type(uint48).max;
            for (uint256 i = pendingMaturitiesLength; i > 0; i--) {
                uint48 maturity = pendingMaturities[i - 1];
                if (maturity <= block.timestamp) {
                    newTotalAssets += uint256(_maturities[maturity].growth) * (maturity - lastUpdate);
                    newGrowth -= _maturities[maturity].growth;
                    removePendingMaturity(i - 1);
                } else if (maturity < newMin) {
                    newMin = maturity;
                }
            }
            nextMaturityFloor = newMin;
            currentGrowth = newGrowth;
        }
        newTotalAssets += uint256(newGrowth) * (block.timestamp - lastUpdate);

        totalAssets = newTotalAssets.toUint128();
        if (block.timestamp != lastUpdate) emit AccrueInterest(newGrowth, newTotalAssets);
        lastUpdate = uint48(block.timestamp);

        return (newGrowth, newTotalAssets);
    }

    /// @dev Returns an estimate of the real assets assigned to the adapter.
    /// @dev Excludes assets reserved for users.
    function realAssets() external view returns (uint256) {
        (, uint256 newTotalAssets) = accrueInterestView();
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
    /// @dev Can be called by a user through forceDeallocate to trigger a sell take by the adapter.
    function deallocate(bytes memory data, uint256 sellerAssets, bytes4 messageSig, address caller)
        external
        returns (bytes32[] memory, int256)
    {
        require(msg.sender == parentVault, NotAuthorized());
        if (messageSig == IVaultV2.forceDeallocate.selector) {
            (Offer memory offer, bytes memory ratifierData) = abi.decode(data, (Offer, bytes));
            require(offer.buy && offer.market.loanToken == asset && offer.tick == MAX_TICK, IncorrectOffer());

            // Already in a deallocate call so we skip the onSell callback and return the deallocation here.
            bytes32 marketId = IdLib.toId(offer.market, block.chainid, midnight);
            uint256 takeUnits = TakeAmountsLib.sellerAssetsToUnits(midnight, marketId, offer, sellerAssets);
            IMidnight(midnight).take(offer, takeUnits, address(this), address(this), address(0), hex"", ratifierData);

            require(IMidnight(midnight).debtOf(marketId, address(this)) == 0, NoBorrowing());

            accrueInterest();
            updateDurationCountAndAllocations(offer.market);
            uint256 newNetCredit = IMidnight(midnight).creditOf(marketId, address(this))
                - IMidnight(midnight).pendingFee(marketId, address(this));
            // new net credit cannot be > old credit
            uint256 totalNetCreditDecrease = netCredit[marketId] - newNetCredit;

            if (totalNetCreditDecrease > 0) {
                removeUnits(marketId, offer.market.maturity, totalNetCreditDecrease);
            }

            emit ForceDeallocate(marketId, sellerAssets, totalNetCreditDecrease);
            return (ids(offer.market), -totalNetCreditDecrease.toInt256());
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
        uint256 timeToMaturity = market.maturity.zeroFloorSub(block.timestamp);
        uint256 buyNetCreditIncrease = boughtCredit - buyPendingFeeIncrease;

        require(msg.sender == midnight, NotMidnight());
        require(buyer == address(this), NotSelf());
        require(buyNetCreditIncrease >= paidAssets, BuyAtLoss());

        uint256 newNetCredit = IMidnight(midnight).creditOf(marketId, address(this))
            - IMidnight(midnight).pendingFee(marketId, address(this));
        int256 change = newNetCredit.toInt256() - netCredit[marketId].toInt256();

        accrueInterest();
        updateDurationCountAndAllocations(market);

        // change is at most buyNetCreditIncrease
        if (change < buyNetCreditIncrease.toInt256()) {
            // forge-lint: disable-next-item(unsafe-typecast) safe because change < buyNetCreditIncrease (checked
            // above).
            uint256 loss = uint256(int256(buyNetCreditIncrease) - change);
            removeUnits(marketId, market.maturity, loss);
        }

        IVaultV2(parentVault).allocate(address(this), abi.encode(ids(market), change), paidAssets);

        if (timeToMaturity > 0) {
            uint128 gainedGrowth = ((buyNetCreditIncrease - paidAssets) / timeToMaturity).toUint128();
            totalAssets += (paidAssets + (buyNetCreditIncrease - paidAssets) % timeToMaturity).toUint128();
            maturityData.growth += gainedGrowth;
            currentGrowth += gainedGrowth;
        } else {
            totalAssets += buyNetCreditIncrease.toUint128();
        }

        maturityData.netCredit += buyNetCreditIncrease.toUint128();
        netCredit[marketId] += buyNetCreditIncrease.toUint128();

        // Insert the maturity in the list if needed
        if (
            maturityData.netCredit == buyNetCreditIncrease && buyNetCreditIncrease > 0
                && market.maturity > block.timestamp
        ) {
            maturityData.index = pendingMaturitiesLength;
            pendingMaturities[pendingMaturitiesLength] = market.maturity.toUint48();
            pendingMaturitiesLength++;
            if (market.maturity < nextMaturityFloor) nextMaturityFloor = market.maturity.toUint48();
            emit InsertMaturity(market.maturity);
        }

        emit Buy(marketId, paidAssets, buyNetCreditIncrease, change);
        return CALLBACK_SUCCESS;
    }

    function onSell(
        bytes32 marketId,
        Market memory market,
        uint256 sellerAssets,
        uint256,
        uint256,
        address seller,
        address,
        bytes memory
    ) external returns (bytes32) {
        uint256 vaultTotalAssetsBefore = IVaultV2(parentVault).totalAssets();
        uint256 newNetCredit = IMidnight(midnight).creditOf(marketId, address(this))
            - IMidnight(midnight).pendingFee(marketId, address(this));
        // new net credit cannot be > old credit
        uint256 totalNetCreditDecrease = netCredit[marketId] - newNetCredit;

        require(msg.sender == midnight, NotMidnight());
        require(seller == address(this), NotSelf());

        accrueInterest();
        updateDurationCountAndAllocations(market);

        if (totalNetCreditDecrease > 0) {
            removeUnits(marketId, market.maturity, totalNetCreditDecrease);
        }

        IVaultV2(parentVault)
            .deallocate(address(this), abi.encode(ids(market), -totalNetCreditDecrease.toInt256()), sellerAssets);

        uint256 vaultRealAssetsAfter = IERC20(asset).balanceOf(address(parentVault));
        uint256 adaptersLength = IVaultV2(parentVault).adaptersLength();
        for (uint256 i = 0; i < adaptersLength; i++) {
            vaultRealAssetsAfter += IAdapter(IVaultV2(parentVault).adapters(i)).realAssets();
        }
        require(vaultRealAssetsAfter >= vaultTotalAssetsBefore, BufferTooLow());

        emit Sell(marketId, sellerAssets, totalNetCreditDecrease);
        return CALLBACK_SUCCESS;
    }

    /* INTERNAL FUNCTIONS */

    /// @dev Removes units from tracking.
    /// @dev Changes the implied price of the market as little as possible.
    function removeUnits(bytes32 marketId, uint256 maturity, uint256 removedUnits) internal {
        MaturityData storage maturityData = _maturities[maturity];

        if (maturity > block.timestamp) {
            uint256 timeToMaturity = maturity - block.timestamp;
            uint128 removedGrowth = maturityData.growth.mulDivUp(removedUnits, maturityData.netCredit).toUint128();
            maturityData.growth -= removedGrowth;
            currentGrowth -= removedGrowth;
            totalAssets = (totalAssets + (removedGrowth * timeToMaturity) - removedUnits).toUint128();
        } else {
            totalAssets -= removedUnits.toUint128();
        }
        maturityData.netCredit -= removedUnits.toUint128();
        netCredit[marketId] -= removedUnits.toUint128();

        if (removedUnits > 0 && maturityData.netCredit == 0 && maturity > block.timestamp) {
            removePendingMaturity(maturityData.index);
        }
    }

    /// @dev Remove the maturity at index.
    /// @dev The slot at the old last index is left with stale data.
    function removePendingMaturity(uint256 index) internal {
        emit RemoveMaturity(pendingMaturities[index]);
        pendingMaturitiesLength--;
        uint48 lastMaturity = pendingMaturities[pendingMaturitiesLength];
        pendingMaturities[index] = lastMaturity;
        _maturities[lastMaturity].index = uint8(index);
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
