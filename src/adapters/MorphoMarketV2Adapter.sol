// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Morpho Association
pragma solidity 0.8.28;

import {MorphoV2} from "lib/morpho-v2/src/MorphoV2.sol";
import {Offer, Signature, Obligation, Collateral, Seizure, Proof} from "lib/morpho-v2/src/interfaces/IMorphoV2.sol";
import {IERC20} from "../interfaces/IERC20.sol";
import {SafeERC20Lib} from "../libraries/SafeERC20Lib.sol";
import {MathLib} from "../libraries/MathLib.sol";
import {MathLib as MorphoV2MathLib} from "lib/morpho-v2/src/libraries/MathLib.sol";
import {IVaultV2} from "../interfaces/IVaultV2.sol";
import {IMorphoMarketV2Adapter, ObligationPosition, Maturity, IAdapter} from "./interfaces/IMorphoMarketV2Adapter.sol";
import {DurationsLib, MAX_DURATIONS} from "./libraries/DurationsLib.sol";

/// @dev Approximates held assets by linearly accounting for interest separately for each obligation.
/// @dev Losses are immdiately accounted minus a discount applied to the remaining interest to be earned, in proportion
/// to the relative sizes of the loss and the adapter's position in the obligation hit by the loss.
/// @dev The adapter must have the allocator role in its parent vault to be able to buy & sell obligations.
contract MorphoMarketV2Adapter is IMorphoMarketV2Adapter {
    using MathLib for uint256;
    using DurationsLib for bytes32;

    /* IMMUTABLES */

    address public immutable asset;
    address public immutable parentVault;
    address public immutable morphoV2;
    bytes32 public immutable adapterId;

    /* MANAGEMENT */

    address public skimRecipient;

    /* ACCOUNTING */

    uint256 public _totalAssets;
    uint48 public lastUpdate;
    uint48 public firstMaturity;
    uint128 public currentGrowth;
    mapping(uint256 timestamp => Maturity) public _maturities;
    mapping(bytes32 obligationId => ObligationPosition) public _positions;
    bytes32 public _durations;
    /* CONSTRUCTOR */

    constructor(address _parentVault, address _morphoV2) {
        asset = IVaultV2(_parentVault).asset();
        parentVault = _parentVault;
        morphoV2 = _morphoV2;
        lastUpdate = uint48(block.timestamp);
        SafeERC20Lib.safeApprove(asset, _morphoV2, type(uint256).max);
        SafeERC20Lib.safeApprove(asset, _parentVault, type(uint256).max);
        firstMaturity = type(uint48).max;
        adapterId = keccak256(abi.encode("this", address(this)));
    }

    /* GETTERS */

    function positions(bytes32 obligationId) public view returns (ObligationPosition memory) {
        return _positions[obligationId];
    }

    function maturities(uint256 date) public view returns (Maturity memory) {
        return _maturities[date];
    }

    function durations() external view returns (uint256[] memory) {
        uint256[] memory durationsArray = new uint256[](MAX_DURATIONS);
        uint256 durationsCount = 0;
        for (uint256 i = 0; i < MAX_DURATIONS; i++) {
            uint256 duration = _durations.get(i);
            if (duration != 0) durationsArray[durationsCount++] = duration;
        }
        assembly ("memory-safe") {
            mstore(durationsArray, durationsCount)
        }
        return durationsArray;
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

    /* VAULT CURATOR FUNCTIONS */

    /// @dev Adds a new duration to the adapter.
    function addDuration(uint256 addedDuration) external {
        require(msg.sender == IVaultV2(parentVault).curator(), NotAuthorized());
        require(addedDuration != 0, IncorrectDuration());
        uint256 freePosition = type(uint256).max;
        for (uint256 i = 0; i < MAX_DURATIONS; i++) {
            uint256 duration = _durations.get(i);
            require(addedDuration != duration, NoDuplicates());
            if (duration == 0 && freePosition == type(uint256).max) freePosition = i;
        }
        if (freePosition == type(uint256).max) revert MaxDurationsExceeded();
        _durations = _durations.set(freePosition, addedDuration);
        emit AddDuration(addedDuration);
    }

    /// @dev Future obligation that match this duration will no longer consume the duration cap in the vault.
    function removeDuration(uint256 removedDuration) external {
        require(msg.sender == IVaultV2(parentVault).curator(), NotAuthorized());
        for (uint256 i = 0; i < MAX_DURATIONS; i++) {
            if (_durations.get(i) == removedDuration) {
                _durations = _durations.set(i, 0);
                break;
            }
        }
        emit RemoveDuration(removedDuration);
    }

    /* VAULT ALLOCATORS FUNCTIONS */

    // Do not cleanup the linked list if we end up at 0 growth
    function withdraw(Obligation memory obligation, uint256 obligationUnits, uint256 shares) external {
        require(IVaultV2(parentVault).isAllocator(msg.sender), NotAuthorized());
        (obligationUnits, shares) = MorphoV2(morphoV2).withdraw(obligation, obligationUnits, shares, address(this));
        removeUnits(obligation, obligationUnits);
        IVaultV2(parentVault).deallocate(address(this), abi.encode(obligationUnits, ids(obligation)), obligationUnits);
    }

    /* ACCRUAL */

    function accrueInterestView() public view returns (uint48, uint128, uint256) {
        uint256 lastChange = lastUpdate;
        uint48 nextMaturity = firstMaturity;
        uint128 newGrowth = currentGrowth;
        uint256 gainedAssets;

        while (nextMaturity < block.timestamp) {
            gainedAssets += uint256(newGrowth) * (nextMaturity - lastChange);
            newGrowth -= _maturities[nextMaturity].growthLostAtMaturity;
            lastChange = nextMaturity;
            nextMaturity = _maturities[nextMaturity].nextMaturity;
        }

        gainedAssets += uint256(newGrowth) * (block.timestamp - lastChange);

        return (nextMaturity, newGrowth, _totalAssets + gainedAssets);
    }

    function accrueInterest() public {
        if (lastUpdate != block.timestamp) {
            (uint48 nextMaturity, uint128 newGrowth, uint256 newTotalAssets) = accrueInterestView();
            _totalAssets = newTotalAssets;
            lastUpdate = uint48(block.timestamp);
            firstMaturity = nextMaturity;
            currentGrowth = newGrowth;
        }
    }

    /// @dev Returns an estimate of the real assets.
    function realAssets() external view returns (uint256) {
        (,, uint256 newTotalAssets) = accrueInterestView();
        return newTotalAssets;
    }

    /* LOSS REALIZATION */

    function realizeLoss(Obligation memory obligation) external {
        bytes32 obligationId = _obligationId(obligation);
        uint256 remainingUnits = MorphoV2(morphoV2).sharesOf(address(this), obligationId)
            .mulDivDown(
                MorphoV2(morphoV2).totalUnits(obligationId) + 1, MorphoV2(morphoV2).totalShares(obligationId) + 1
            );

        uint256 lostUnits = _positions[obligationId].units - remainingUnits;
        removeUnits(obligation, lostUnits);
        IVaultV2(parentVault).deallocate(address(this), abi.encode(lostUnits, ids(obligation)), 0);
    }

    /* ALLOCATION FUNCTIONS */

    /// @dev Can only be called from a buy callback where the adapter is the maker.
    function allocate(bytes memory data, uint256, bytes4, address vaultAllocator)
        external
        view
        returns (bytes32[] memory, int256)
    {
        require(vaultAllocator == address(this), SelfAllocationOnly());
        (uint256 obligationUnits, bytes32[] memory _ids) = abi.decode(data, (uint256, bytes32[]));
        return (_ids, obligationUnits.toInt256());
    }

    /// @dev Can be called from vault.deallocate from a sell callback where the adapter is the maker,
    /// @dev or from vault.forceDeallocate to trigger a sell take by the adapter.
    function deallocate(bytes memory data, uint256 sellerAssets, bytes4 messageSig, address caller)
        external
        returns (bytes32[] memory, int256)
    {
        if (messageSig == IVaultV2.forceDeallocate.selector) {
            (Offer memory offer, Proof memory proof, Signature memory signature) =
                abi.decode(data, (Offer, Proof, Signature));
            require(
                offer.buy && offer.obligation.loanToken == asset && offer.startPrice == 1e18
                    && offer.expiryPrice == 1e18,
                IncorrectOffer()
            );

            (,, uint256 obligationUnits,) = MorphoV2(morphoV2)
                .take(0, sellerAssets, 0, 0, address(this), offer, proof, signature, address(0), hex"");

            require(MorphoV2(morphoV2).debtOf(address(this), _obligationId(offer.obligation)) == 0, NoBorrowing());

            removeUnits(offer.obligation, obligationUnits);
            return (ids(offer.obligation), -obligationUnits.toInt256());
        } else {
            require(caller == address(this), SelfAllocationOnly());
            (uint256 obligationUnits, bytes32[] memory _ids) = abi.decode(data, (uint256, bytes32[]));
            return (_ids, -obligationUnits.toInt256());
        }
    }

    /* MORPHO V2 CALLBACKS */

    function onRatify(Offer memory offer, address signer) external view returns (bool) {
        // Collaterals will be checked at the level of vault ids.
        require(msg.sender == address(morphoV2), NotMorphoV2());
        require(offer.obligation.loanToken == asset, LoanAssetMismatch());
        require(offer.maker == address(this), IncorrectOwner());
        require(offer.callback == address(this), IncorrectCallbackAddress());
        require(bytes32(offer.callbackData) != "forceDeallocate", IncorrectCallbackData());
        require(offer.start <= block.timestamp, IncorrectStart());
        // uint48.max is the list end pointer
        require(offer.obligation.maturity < type(uint48).max, IncorrectMaturity());
        require(IVaultV2(parentVault).isAllocator(signer), IncorrectSigner());
        return true;
    }

    function onBuy(
        Obligation memory obligation,
        address buyer,
        uint256 buyerAssets,
        uint256,
        uint256 obligationUnits,
        uint256,
        bytes memory data
    ) external {
        require(msg.sender == address(morphoV2), NotMorphoV2());
        require(buyer == address(this), NotSelf());
        bytes32 obligationId = _obligationId(obligation);
        uint48 prevMaturity = abi.decode(data, (uint48));
        require(prevMaturity < obligation.maturity, IncorrectHint());

        accrueInterest();
        if (obligation.maturity > block.timestamp) {
            uint128 timeToMaturity = uint128(obligation.maturity - block.timestamp);
            uint128 gainedGrowth = ((obligationUnits - buyerAssets) / timeToMaturity).toUint128();
            _totalAssets += buyerAssets + (obligationUnits - buyerAssets) % timeToMaturity;
            _positions[obligationId].growth += gainedGrowth;
            _maturities[obligation.maturity].growthLostAtMaturity += gainedGrowth;
            currentGrowth += gainedGrowth;
        } else {
            _totalAssets += obligationUnits;
        }

        _positions[obligationId].units += obligationUnits.toUint128();

        uint48 nextMaturity;
        if (prevMaturity == 0) {
            nextMaturity = firstMaturity;
        } else {
            nextMaturity = _maturities[prevMaturity].nextMaturity;
            require(nextMaturity != 0, IncorrectHint());
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

        IVaultV2(parentVault).allocate(address(this), abi.encode(obligationUnits, ids(obligation)), buyerAssets);
    }

    function onSell(
        Obligation memory obligation,
        address seller,
        uint256,
        uint256 sellerAssets,
        uint256 obligationUnits,
        uint256,
        bytes memory
    ) external {
        require(msg.sender == address(morphoV2), NotMorphoV2());
        require(seller == address(this), NotSelf());
        require(MorphoV2(morphoV2).debtOf(seller, _obligationId(obligation)) == 0, NoBorrowing());

        uint256 vaultRealAssets = IERC20(asset).balanceOf(address(parentVault));
        uint256 adaptersLength = IVaultV2(parentVault).adaptersLength();
        for (uint256 i = 0; i < adaptersLength; i++) {
            vaultRealAssets += IAdapter(IVaultV2(parentVault).adapters(i)).realAssets();
        }
        uint256 vaultBuffer = vaultRealAssets.zeroFloorSub(IVaultV2(parentVault).totalAssets());

        uint256 _totalAssetsBefore = _totalAssets;
        removeUnits(obligation, obligationUnits);
        require(vaultBuffer >= _totalAssetsBefore.zeroFloorSub(_totalAssets), BufferTooLow());

        IVaultV2(parentVault).deallocate(address(this), abi.encode(obligationUnits, ids(obligation)), sellerAssets);
    }

    /// INTERNAL FUNCTIONS ///

    /// @dev The total assets can go up after removing units to compensate for the rounded up lost growth.
    function removeUnits(Obligation memory obligation, uint256 removedUnits) internal {
        accrueInterest();
        bytes32 obligationId = _obligationId(obligation);
        if (obligation.maturity > block.timestamp) {
            uint256 timeToMaturity = obligation.maturity - block.timestamp;
            uint128 removedGrowth = uint256(_positions[obligationId].growth)
                .mulDivUp(removedUnits, _positions[obligationId].units).toUint128();
            _maturities[obligation.maturity].growthLostAtMaturity -= removedGrowth;
            _positions[obligationId].growth -= removedGrowth;
            _positions[obligationId].units -= removedUnits.toUint128();
            _totalAssets = _totalAssets + (removedGrowth * timeToMaturity) - removedUnits;
        } else {
            _totalAssets -= removedUnits;
            _positions[obligationId].units -= removedUnits.toUint128();
        }
    }

    function _obligationId(Obligation memory obligation) internal pure returns (bytes32) {
        return keccak256(abi.encode(obligation));
    }

    function ids(Obligation memory obligation) public view returns (bytes32[] memory) {
        uint256 baseLength = 1 + obligation.collaterals.length * 2;
        bytes32[] memory _ids = new bytes32[](baseLength + MAX_DURATIONS);
        uint256 j = 0;
        _ids[j++] = adapterId;
        for (uint256 i = 0; i < obligation.collaterals.length; i++) {
            address collateralToken = obligation.collaterals[i].token;
            _ids[j++] = keccak256(abi.encode("collateralToken", collateralToken));
            _ids[j++] = keccak256(
                abi.encode(
                    "collateral", collateralToken, obligation.collaterals[i].oracle, obligation.collaterals[i].lltv
                )
            );
        }
        uint256 timeToMaturity = (obligation.maturity - block.timestamp);
        uint256 durationIdCount = 0;
        for (uint256 i = 0; i < MAX_DURATIONS; i++) {
            uint256 duration = _durations.get(i);

            if (duration != 0 && timeToMaturity >= duration) {
                durationIdCount++;
                _ids[j++] = keccak256(abi.encode("duration", duration));
            }
        }
        assembly ("memory-safe") {
            mstore(_ids, add(baseLength, durationIdCount))
        }
        return _ids;
    }

    function onLiquidate(Seizure[] memory, address, address, bytes memory) external pure {
        revert();
    }
}
