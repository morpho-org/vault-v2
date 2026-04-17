// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Morpho Association
pragma solidity 0.8.34;

import {IMidnight, Offer, Obligation} from "lib/midnight/src/interfaces/IMidnight.sol";
import {MAX_TICK} from "lib/midnight/src/libraries/TickLib.sol";
import {Signature, EIP712_DOMAIN_TYPEHASH, ROOT_TYPEHASH} from "lib/midnight/src/interfaces/IEcrecover.sol";
import {CALLBACK_SUCCESS} from "lib/midnight/src/libraries/ConstantsLib.sol";
import {TakeAmountsLib} from "lib/midnight/src/periphery/TakeAmountsLib.sol";
import {IdLib} from "lib/midnight/src/libraries/IdLib.sol";
import {IERC20} from "../interfaces/IERC20.sol";
import {SafeERC20Lib} from "../libraries/SafeERC20Lib.sol";
import {MathLib} from "../libraries/MathLib.sol";
import {IVaultV2} from "../interfaces/IVaultV2.sol";
import {IMidnightAdapter, MaturityData, IAdapter} from "./interfaces/IMidnightAdapter.sol";
import {DurationsLib} from "./libraries/DurationsLib.sol";

/// @dev Approximates held assets by linearly accounting for interest separately for each obligation.
/// @dev Losses are immediately accounted minus a discount applied to the remaining interest to be earned, in proportion
/// to the relative sizes of the loss and the adapter's position in the obligation hit by the loss.
/// @dev The adapter must have the allocator role in its parent vault to be able to buy & sell obligations.
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
    bytes32 public immutable packedDurations;
    uint256 public immutable durationsLength;

    /* MANAGEMENT */

    address public skimRecipient;

    /* ACCOUNTING */

    uint256 public _totalAssets;
    uint48 public lastUpdate;
    uint48 public firstMaturity;
    uint128 public currentGrowth;
    mapping(uint256 timestamp => MaturityData) public _maturities;
    mapping(bytes32 obligationId => uint256) public netCredit;
    /* CONSTRUCTOR */

    constructor(address _parentVault, address _midnight, uint256[] memory _durations) {
        asset = IVaultV2(_parentVault).asset();
        parentVault = _parentVault;
        midnight = _midnight;
        lastUpdate = uint48(block.timestamp);
        SafeERC20Lib.safeApprove(asset, _midnight, type(uint256).max);
        SafeERC20Lib.safeApprove(asset, _parentVault, type(uint256).max);
        firstMaturity = type(uint48).max;
        adapterId = keccak256(abi.encode("this", address(this)));

        bytes32 _packedDurations;
        uint256 currentDuration;
        for (uint256 i = 0; i < _durations.length; i++) {
            require(_durations[i] > currentDuration, IncorrectDuration());
            currentDuration = _durations[i];
            _packedDurations = _packedDurations.set(i, _durations[i]);
        }
        packedDurations = _packedDurations;
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

    function withdrawToVault(Obligation memory obligation, uint256 withdrawnAssets) external {
        require(IVaultV2(parentVault).isAllocator(msg.sender), NotAuthorized());
        bytes32 obligationId = IdLib.toId(obligation, block.chainid, midnight);
        uint256 pendingFeeDecrease =
            IMidnight(midnight).withdraw(obligation, withdrawnAssets, address(this), address(this));
        uint256 newNetCredit = IMidnight(midnight).creditOf(obligationId, address(this))
            - IMidnight(midnight).pendingFee(obligationId, address(this));
        // new net credit cannot be > old credit
        uint256 totalNetCreditDecrease = netCredit[obligationId] - newNetCredit;

        accrueInterest();
        updateDurationIndexAndAllocations(obligation);

        if (totalNetCreditDecrease > 0) removeUnits(obligationId, obligation.maturity, totalNetCreditDecrease);

        int256 change = -int256(totalNetCreditDecrease);
        IVaultV2(parentVault).deallocate(address(this), abi.encode(ids(obligation), change), withdrawnAssets);
    }

    function updateDurationIndexAndAllocations(Obligation memory obligation) public {
        MaturityData storage maturityData = _maturities[obligation.maturity];
        uint256 oldDurationIndex = maturityData.durationIndex;
        uint256 newDurationIndex = durationIndex(obligation.maturity);
        maturityData.durationIndex = uint8(newDurationIndex);
        // VaultV2.deallocate requires allocation > 0 for each returned id.
        if (newDurationIndex < oldDurationIndex && maturityData.netCredit > 0) {
            bytes32[] memory zeroedDurationsIds = new bytes32[](oldDurationIndex - newDurationIndex);
            for (uint256 i = 0; i < zeroedDurationsIds.length; i++) {
                zeroedDurationsIds[i] = keccak256(abi.encode("duration", packedDurations.get(newDurationIndex + i)));
            }
            int256 change = -int256(uint256(maturityData.netCredit));
            IVaultV2(parentVault).deallocate(address(this), abi.encode(zeroedDurationsIds, change), 0);
        }
    }

    /* ACCRUAL */

    function accrueInterestView() public view returns (uint48, uint128, uint256) {
        uint256 lastChange = lastUpdate;
        uint48 nextMaturity = firstMaturity;
        uint128 newGrowth = currentGrowth;
        uint256 gainedAssets;

        while (nextMaturity < block.timestamp) {
            gainedAssets += uint256(newGrowth) * (nextMaturity - lastChange);
            newGrowth -= _maturities[nextMaturity].growth;
            lastChange = nextMaturity;
            nextMaturity = _maturities[nextMaturity].nextMaturity;
        }

        gainedAssets += uint256(newGrowth) * (block.timestamp - lastChange);

        return (nextMaturity, newGrowth, _totalAssets + gainedAssets);
    }

    function accrueInterest() public returns (uint48, uint128, uint256) {
        if (lastUpdate != block.timestamp) {
            (firstMaturity, currentGrowth, _totalAssets) = accrueInterestView();
            lastUpdate = uint48(block.timestamp);
        }
        return (firstMaturity, currentGrowth, _totalAssets);
    }

    /// @dev Returns an estimate of the real assets assigned to the adapter.
    /// @dev Excludes assets reserved for users.
    function realAssets() external view returns (uint256) {
        (,, uint256 newTotalAssets) = accrueInterestView();
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
            (Offer memory offer, bytes memory ratifierData, bytes32 root, bytes32[] memory proof) =
                abi.decode(data, (Offer, bytes, bytes32, bytes32[]));
            require(offer.buy && offer.obligation.loanToken == asset && offer.tick == MAX_TICK, IncorrectOffer());

            // Already in a deallocate call so we skip the onSell callback and return the deallocation here.
            bytes32 obligationId = IdLib.toId(offer.obligation, block.chainid, midnight);
            uint256 takeUnits =
                TakeAmountsLib.sellerAssetsToUnits(IMidnight(midnight), obligationId, offer, sellerAssets);
            IMidnight(midnight)
                .take(takeUnits, address(this), address(0), hex"", address(this), offer, ratifierData, root, proof);

            require(IMidnight(midnight).debtOf(obligationId, address(this)) == 0, NoBorrowing());

            accrueInterest();
            updateDurationIndexAndAllocations(offer.obligation);
            uint256 newNetCredit = IMidnight(midnight).creditOf(obligationId, address(this))
                - IMidnight(midnight).pendingFee(obligationId, address(this));
            // new net credit cannot be > old credit
            uint256 totalNetCreditDecrease = netCredit[obligationId] - newNetCredit;

            if (totalNetCreditDecrease > 0) {
                removeUnits(obligationId, offer.obligation.maturity, totalNetCreditDecrease);
            }

            int256 change = -int256(totalNetCreditDecrease);
            return (ids(offer.obligation), change);
        } else {
            require(caller == address(this), SelfAllocationOnly());
            // Return exactly the data passed to the function.
            assembly ("memory-safe") {
                return(add(data, 32), mload(data))
            }
        }
    }

    /* MIDNIGHT CALLBACKS */

    function onRatify(Offer memory offer, bytes32 root, bytes memory data) external view returns (bytes32) {
        // Collaterals will be checked through vault ids.
        require(offer.obligation.loanToken == asset, LoanAssetMismatch());
        require(offer.maker == address(this), IncorrectOwner());
        require(offer.callback == address(this), IncorrectCallbackAddress());
        require(offer.start <= block.timestamp, IncorrectStart());
        // uint48.max is the list end pointer
        require(offer.obligation.maturity < type(uint48).max, IncorrectMaturity());
        require(offer.buy || offer.reduceOnly, NoDebtCreation());

        Signature memory sig = abi.decode(data, (Signature));
        bytes32 structHash = keccak256(abi.encode(ROOT_TYPEHASH, root));
        bytes32 domainSeparator = keccak256(abi.encode(EIP712_DOMAIN_TYPEHASH, block.chainid, address(this)));
        bytes32 digest = keccak256(bytes.concat("\x19\x01", domainSeparator, structHash));
        address signer = ecrecover(digest, sig.v, sig.r, sig.s);
        require(signer != address(0), IncorrectSigner());
        require(IVaultV2(parentVault).isAllocator(signer), IncorrectSigner());

        return CALLBACK_SUCCESS;
    }

    function onBuy(
        bytes32 obligationId,
        Obligation memory obligation,
        address buyer,
        uint256 paidAssets,
        uint256 boughtCredit,
        uint256 buyPendingFeeIncrease,
        bytes memory data
    ) external returns (bytes32) {
        uint48 prevMaturity = abi.decode(data, (uint48));
        MaturityData storage maturityData = _maturities[obligation.maturity];
        uint256 buyNetCreditIncrease = boughtCredit - buyPendingFeeIncrease;
        uint256 timeToMaturity = obligation.maturity.zeroFloorSub(block.timestamp);

        require(msg.sender == midnight, NotMidnight());
        require(buyer == address(this), NotSelf());
        require(prevMaturity < obligation.maturity, IncorrectHint());
        require(buyNetCreditIncrease >= paidAssets, BuyAtLoss());

        uint256 newNetCredit = IMidnight(midnight).creditOf(obligationId, address(this))
            - IMidnight(midnight).pendingFee(obligationId, address(this));
        int256 change = newNetCredit.toInt256() - netCredit[obligationId].toInt256();

        accrueInterest();
        updateDurationIndexAndAllocations(obligation);

        // change is at most buyNetCreditIncrease
        if (change < buyNetCreditIncrease.toInt256()) {
            uint256 loss = (int256(buyNetCreditIncrease) - change).toUint256();
            removeUnits(obligationId, obligation.maturity, loss);
        }

        IVaultV2(parentVault).allocate(address(this), abi.encode(ids(obligation), change), paidAssets);

        if (timeToMaturity > 0) {
            uint128 gainedGrowth = ((buyNetCreditIncrease - paidAssets) / timeToMaturity).toUint128();
            _totalAssets += paidAssets + (buyNetCreditIncrease - paidAssets) % timeToMaturity;
            maturityData.growth += gainedGrowth;
            currentGrowth += gainedGrowth;
        } else {
            _totalAssets += buyNetCreditIncrease;
        }

        maturityData.netCredit += buyNetCreditIncrease.toUint128();
        netCredit[obligationId] += buyNetCreditIncrease.toUint128();

        // Insert the maturity in the list if needed
        if (obligation.maturity >= block.timestamp) {
            uint48 nextMaturity;
            if (prevMaturity == 0) {
                nextMaturity = firstMaturity;
            } else {
                require(prevMaturity >= block.timestamp, IncorrectHint());
                nextMaturity = _maturities[prevMaturity].nextMaturity;
                require(nextMaturity > 0, IncorrectHint());
            }

            while (nextMaturity < obligation.maturity) {
                prevMaturity = nextMaturity;
                nextMaturity = _maturities[prevMaturity].nextMaturity;
            }

            if (nextMaturity > obligation.maturity) {
                _maturities[obligation.maturity].nextMaturity = nextMaturity;
                if (prevMaturity == 0) {
                    firstMaturity = obligation.maturity.toUint48();
                } else {
                    _maturities[prevMaturity].nextMaturity = obligation.maturity.toUint48();
                }
            }
        }

        return CALLBACK_SUCCESS;
    }

    function onSell(
        bytes32 obligationId,
        Obligation memory obligation,
        address seller,
        uint256 sellerAssets,
        uint256 units,
        uint256 sellPendingFeeDecrease,
        bytes memory
    ) external returns (bytes32) {
        uint256 vaultTotalAssetsBefore = IVaultV2(parentVault).totalAssets();
        uint256 newNetCredit = IMidnight(midnight).creditOf(obligationId, address(this))
            - IMidnight(midnight).pendingFee(obligationId, address(this));
        // new net credit cannot be > old credit
        uint256 totalNetCreditDecrease = netCredit[obligationId] - newNetCredit;

        require(msg.sender == midnight, NotMidnight());
        require(seller == address(this), NotSelf());

        accrueInterest();
        updateDurationIndexAndAllocations(obligation);

        if (totalNetCreditDecrease > 0) removeUnits(obligationId, obligation.maturity, totalNetCreditDecrease);

        int256 change = -int256(totalNetCreditDecrease);
        IVaultV2(parentVault).deallocate(address(this), abi.encode(ids(obligation), change), sellerAssets);

        uint256 vaultRealAssetsAfter = IERC20(asset).balanceOf(address(parentVault));
        uint256 adaptersLength = IVaultV2(parentVault).adaptersLength();
        for (uint256 i = 0; i < adaptersLength; i++) {
            vaultRealAssetsAfter += IAdapter(IVaultV2(parentVault).adapters(i)).realAssets();
        }
        require(vaultRealAssetsAfter >= vaultTotalAssetsBefore, BufferTooLow());

        return CALLBACK_SUCCESS;
    }

    /* INTERNAL FUNCTIONS */

    /// @dev Removes units from tracking.
    /// @dev Changes the implied price of the obligation as little as possible.
    function removeUnits(bytes32 obligationId, uint256 maturity, uint256 removedUnits) internal {
        MaturityData storage maturityData = _maturities[maturity];

        if (maturity > block.timestamp) {
            uint256 timeToMaturity = maturity - block.timestamp;
            uint128 removedGrowth = maturityData.growth.mulDivUp(removedUnits, maturityData.netCredit).toUint128();
            maturityData.growth -= removedGrowth;
            currentGrowth -= removedGrowth;
            _totalAssets = _totalAssets + (removedGrowth * timeToMaturity) - removedUnits;
        } else {
            _totalAssets -= removedUnits;
        }
        maturityData.netCredit -= removedUnits.toUint128();
        netCredit[obligationId] -= removedUnits.toUint128();
    }

    function durationIndex(uint256 maturity) internal view returns (uint256 index) {
        uint256 timeToMaturity = maturity.zeroFloorSub(block.timestamp);
        while (index < durationsLength && timeToMaturity >= packedDurations.get(index)) index++;
    }

    function ids(Obligation memory obligation) public view returns (bytes32[] memory) {
        uint256 durationsCount = durationIndex(obligation.maturity);

        bytes32[] memory idsArray = new bytes32[](1 + obligation.collateralParams.length * 2 + durationsCount);

        uint256 j;
        idsArray[j++] = adapterId;
        for (uint256 i = 0; i < obligation.collateralParams.length; i++) {
            address collateralToken = obligation.collateralParams[i].token;
            idsArray[j++] = keccak256(abi.encode("collateralToken", collateralToken));
            idsArray[j++] = keccak256(
                abi.encode(
                    "collateral",
                    collateralToken,
                    obligation.collateralParams[i].oracle,
                    obligation.collateralParams[i].lltv
                )
            );
        }
        for (uint256 i = 0; i < durationsCount; i++) {
            idsArray[j++] = keccak256(abi.encode("duration", packedDurations.get(i)));
        }

        return idsArray;
    }

    /* UNUSED CALLBACKS */

    function onLiquidate(bytes32, Obligation memory, uint256, uint256, uint256, address, bytes memory) external pure {
        revert();
    }

    function onRepay(bytes32, Obligation memory, uint256, address, bytes memory) external pure {
        revert();
    }
}
