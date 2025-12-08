// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Morpho Association
pragma solidity 0.8.28;

import {MorphoV2} from "lib/morpho-v2/src/MorphoV2.sol";
import {Offer, Signature, Obligation, Seizure, Proof} from "lib/morpho-v2/src/interfaces/IMorphoV2.sol";
import {IERC20} from "../interfaces/IERC20.sol";
import {SafeERC20Lib} from "../libraries/SafeERC20Lib.sol";
import {MathLib} from "../libraries/MathLib.sol";
import {IVaultV2} from "../interfaces/IVaultV2.sol";
import {
    IMorphoMarketV2Adapter,
    ObligationPosition,
    Maturity,
    IAdapter,
    MAX_DURATIONS
} from "./interfaces/IMorphoMarketV2Adapter.sol";

/// @dev Approximates held assets by linearly accounting for interest separately for each obligation.
/// @dev Losses are immdiately accounted minus a discount applied to the remaining interest to be earned, in proportion
/// to the relative sizes of the loss and the adapter's position in the obligation hit by the loss.
/// @dev The adapter must have the allocator role in its parent vault to be able to buy & sell obligations.
contract MorphoMarketV2Adapter is IMorphoMarketV2Adapter {
    using MathLib for uint256;
    using MathLib for uint128;

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
    uint32[8] public _durations;
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
        uint32[8] memory durationsLocal = _durations;
        uint256 durationsCount = 0;
        for (uint256 i = 0; i < MAX_DURATIONS; i++) {
            if (durationsLocal[i] != 0) durationsCount++;
        }

        uint256[] memory durationsArray = new uint256[](durationsCount);
        uint256 j;
        for (uint256 i = 0; i < MAX_DURATIONS; i++) {
            uint256 duration = durationsLocal[i];
            if (duration != 0) durationsArray[j++] = duration;
        }
        return durationsArray;
    }

    function ids(Obligation memory obligation) external view returns (bytes32[] memory) {
        return _ids(obligation, syncedDurations(obligation.maturity));
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
    /// @dev Currently held obligations that match this duration must be touched to be accounted for in the caps.
    function addDuration(uint256 addedDuration) external {
        require(msg.sender == IVaultV2(parentVault).curator(), NotAuthorized());
        require(addedDuration <= type(uint32).max && addedDuration != 0, IncorrectDuration());
        uint32[8] memory localDurations = _durations;
        uint256 newPosition = 8;
        for (uint256 i = 0; i < MAX_DURATIONS; i++) {
            uint32 duration = localDurations[i];
            require(addedDuration != duration, NoDuplicates());
            if (duration == 0 && newPosition == 8) {
                localDurations[i] = uint32(addedDuration);
                newPosition = i;
            }
        }
        if (newPosition == 8) revert MaxDurationsExceeded();
        _durations = localDurations;

        bytes32[] memory durationIdArray = new bytes32[](1);
        durationIdArray[0] = keccak256(abi.encode("duration", addedDuration));

        uint48 nextMaturity = firstMaturity;

        while (nextMaturity < type(uint48).max) {
            if (nextMaturity >= addedDuration) {
                Maturity storage maturity = _maturities[nextMaturity];
                maturity.durations[newPosition] = uint32(addedDuration);
                IVaultV2(parentVault).allocate(address(this), abi.encode(durationIdArray, maturity.units.toInt256()), 0);
            }
            nextMaturity = _maturities[nextMaturity].nextMaturity;
        }
        emit AddDuration(addedDuration);
    }

    /// @dev Future obligation that match this duration will no longer consume the duration cap in the vault.
    /// @dev Currently held obligations that match this duration must be touched to be de-accounted for in the caps.
    function removeDuration(uint256 removedDuration) external {
        require(msg.sender == IVaultV2(parentVault).curator(), NotAuthorized());
        uint32[8] memory localDurations = _durations;
        uint256 oldPosition = 8;
        for (uint256 i = 0; i < MAX_DURATIONS; i++) {
            if (localDurations[i] == removedDuration) {
                localDurations[i] = 0;
                oldPosition = i;
                break;
            }
        }
        if (oldPosition == 8) revert DurationNotFound();
        _durations = localDurations;

        bytes32[] memory durationIdArray = new bytes32[](1);
        durationIdArray[0] = keccak256(abi.encode("duration", removedDuration));

        uint48 nextMaturity = firstMaturity;

        while (nextMaturity < type(uint48).max) {
            if (nextMaturity >= removedDuration) {
                Maturity storage maturity = _maturities[nextMaturity];
                maturity.durations[oldPosition] = 0;
                selfDeallocate(durationIdArray, maturity.units, 0);
            }
            nextMaturity = _maturities[nextMaturity].nextMaturity;
        }

        emit RemoveDuration(removedDuration);
    }

    /* VAULT ALLOCATORS FUNCTIONS */

    function withdraw(Obligation memory obligation, uint256 withdrawn, uint256 shares) external {
        require(IVaultV2(parentVault).isAllocator(msg.sender), NotAuthorized());
        (, shares) = MorphoV2(morphoV2).withdraw(obligation, withdrawn, shares, address(this));
        ObligationPosition storage position = _positions[_obligationId(obligation)];
        Maturity storage maturity = _maturities[obligation.maturity];
        removeUnits(obligation, position, withdrawn);
        bytes32[] memory zeroedDurationsIds = updateDurations(obligation.maturity, maturity);
        if (zeroedDurationsIds.length > 0) {
            selfDeallocate(zeroedDurationsIds, maturity.units, 0);
        }
        selfDeallocate(_ids(obligation, maturity.durations), withdrawn, withdrawn);
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
            (uint48 newFirstMaturity, uint128 newCurrentGrowth, uint256 newTotalAssets) = accrueInterestView();
            _totalAssets = newTotalAssets;
            lastUpdate = uint48(block.timestamp);
            firstMaturity = newFirstMaturity;
            currentGrowth = newCurrentGrowth;
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

        ObligationPosition storage position = _positions[obligationId];
        Maturity storage maturity = _maturities[obligation.maturity];
        uint256 lostUnits = position.units - remainingUnits;
        removeUnits(obligation, position, lostUnits);
        bytes32[] memory zeroedDurationsIds = updateDurations(obligation.maturity, maturity);
        if (zeroedDurationsIds.length > 0) {
            selfDeallocate(zeroedDurationsIds, maturity.units, 0);
        }
        selfDeallocate(_ids(obligation, maturity.durations), lostUnits, 0);
    }

    /* ALLOCATION FUNCTIONS */

    /// @dev Can be called by this adapter from a buy callback.
    function allocate(bytes memory data, uint256, bytes4, address caller)
        external
        view
        returns (bytes32[] memory, int256)
    {
        require(caller == address(this), SelfAllocationOnly());
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
        if (messageSig == IVaultV2.forceDeallocate.selector) {
            (Offer memory offer, Proof memory proof, Signature memory signature) =
                abi.decode(data, (Offer, Proof, Signature));
            require(
                offer.buy && offer.obligation.loanToken == asset && offer.startPrice == 1e18
                    && offer.expiryPrice == 1e18,
                IncorrectOffer()
            );

            (,, uint256 removedObligationUnits,) = MorphoV2(morphoV2)
                .take(0, sellerAssets, 0, 0, address(this), offer, proof, signature, address(0), hex"");

            bytes32 obligationId = _obligationId(offer.obligation);
            require(MorphoV2(morphoV2).debtOf(address(this), obligationId) == 0, NoBorrowing());

            ObligationPosition storage position = _positions[obligationId];
            Maturity storage maturity = _maturities[offer.obligation.maturity];
            removeUnits(offer.obligation, position, removedObligationUnits);
            bytes32[] memory zeroedDurationsIds = updateDurations(offer.obligation.maturity, maturity);
            if (zeroedDurationsIds.length > 0) selfDeallocate(zeroedDurationsIds, maturity.units, 0);
            return (_ids(offer.obligation, maturity.durations), -removedObligationUnits.toInt256());
        } else {
            require(caller == address(this), SelfAllocationOnly());
            assembly ("memory-safe") {
                return(add(data, 32), mload(data))
            }
        }
    }

    /* MORPHO V2 CALLBACKS */

    function onRatify(Offer memory offer, address signer) external view returns (bool) {
        // Collaterals will be checked at the level of vault ids.
        require(msg.sender == address(morphoV2), NotMorphoV2());
        require(offer.obligation.loanToken == asset, LoanAssetMismatch());
        require(offer.maker == address(this), IncorrectOwner());
        require(offer.callback == address(this), IncorrectCallbackAddress());
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
        ObligationPosition storage position = _positions[obligationId];
        Maturity storage maturity = _maturities[obligation.maturity];

        selfDeallocate(_ids(obligation, maturity.durations), position.units, 0);
        accrueInterest();

        if (obligation.maturity > block.timestamp) {
            uint128 timeToMaturity = uint128(obligation.maturity - block.timestamp);
            uint128 gainedGrowth = ((obligationUnits - buyerAssets) / timeToMaturity).toUint128();
            _totalAssets += buyerAssets + (obligationUnits - buyerAssets) % timeToMaturity;
            position.growth += gainedGrowth;
            maturity.growthLostAtMaturity += gainedGrowth;
            currentGrowth += gainedGrowth;
        } else {
            _totalAssets += obligationUnits;
        }

        position.units += obligationUnits.toUint128();
        maturity.units += obligationUnits.toUint128();

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
            maturity.nextMaturity = nextMaturity;
            if (prevMaturity == 0) {
                firstMaturity = obligation.maturity.toUint48();
            } else {
                _maturities[prevMaturity].nextMaturity = obligation.maturity.toUint48();
            }
        }

        updateDurations(obligation.maturity, maturity);
        IVaultV2(parentVault)
            .allocate(
                address(this), abi.encode(_ids(obligation, maturity.durations), position.units.toInt256()), buyerAssets
            );
    }

    function onSell(
        Obligation memory obligation,
        address seller,
        uint256,
        uint256 sellerAssets,
        uint256 soldObligationUnits,
        uint256,
        bytes memory
    ) external {
        bytes32 obligationId = _obligationId(obligation);
        require(msg.sender == address(morphoV2), NotMorphoV2());
        require(seller == address(this), NotSelf());
        require(MorphoV2(morphoV2).debtOf(address(this), obligationId) == 0, NoBorrowing());

        uint256 vaultTotalAssetsBefore = IVaultV2(parentVault).totalAssets();

        ObligationPosition storage position = _positions[obligationId];
        Maturity storage maturity = _maturities[obligation.maturity];
        removeUnits(obligation, position, soldObligationUnits);
        bytes32[] memory zeroedDurationsIds = updateDurations(obligation.maturity, maturity);
        if (zeroedDurationsIds.length > 0) selfDeallocate(zeroedDurationsIds, maturity.units, 0);
        selfDeallocate(_ids(obligation, maturity.durations), soldObligationUnits, sellerAssets);

        uint256 vaultRealAssetsAfter = IERC20(asset).balanceOf(address(parentVault));
        uint256 adaptersLength = IVaultV2(parentVault).adaptersLength();
        for (uint256 i = 0; i < adaptersLength; i++) {
            vaultRealAssetsAfter += IAdapter(IVaultV2(parentVault).adapters(i)).realAssets();
        }
        require(vaultRealAssetsAfter >= vaultTotalAssetsBefore, BufferTooLow());
    }

    /* INTERNAL FUNCTIONS */

    /// @dev The total assets can go up after removing units to compensate for the rounded up lost growth.
    function removeUnits(Obligation memory obligation, ObligationPosition storage position, uint256 removedUnits)
        internal
    {
        accrueInterest();
        Maturity storage maturity = _maturities[obligation.maturity];

        if (obligation.maturity > block.timestamp) {
            uint256 timeToMaturity = obligation.maturity - block.timestamp;
            uint128 removedGrowth = uint256(position.growth).mulDivUp(removedUnits, position.units).toUint128();
            maturity.growthLostAtMaturity -= removedGrowth;
            // Do not cleanup the linked list if we end up at 0 growth.
            position.growth -= removedGrowth;
            currentGrowth -= removedGrowth;
            _totalAssets = _totalAssets + (removedGrowth * timeToMaturity) - removedUnits;
        } else {
            _totalAssets -= removedUnits;
        }
        position.units -= removedUnits.toUint128();
        maturity.units -= removedUnits.toUint128();
    }

    function _obligationId(Obligation memory obligation) internal pure returns (bytes32) {
        return keccak256(abi.encode(obligation));
    }

    function syncedDurations(uint256 maturity) internal view returns (uint32[8] memory) {
        uint32[8] memory localDurations = _durations;
        uint256 timeToMaturity = maturity.zeroFloorSub(block.timestamp);
        for (uint256 i = 0; i < MAX_DURATIONS; i++) {
            if (timeToMaturity < localDurations[i]) localDurations[i] = 0;
        }
        return localDurations;
    }

    function _ids(Obligation memory obligation, uint32[8] memory localDurations)
        internal
        view
        returns (bytes32[] memory)
    {
        uint256 durationIdCount = 0;
        for (uint256 i = 0; i < MAX_DURATIONS; i++) {
            if (localDurations[i] != 0) durationIdCount++;
        }
        bytes32[] memory idsArray = new bytes32[](1 + obligation.collaterals.length * 2 + durationIdCount);

        uint256 j;
        idsArray[j++] = adapterId;
        for (uint256 i = 0; i < obligation.collaterals.length; i++) {
            address collateralToken = obligation.collaterals[i].token;
            idsArray[j++] = keccak256(abi.encode("collateralToken", collateralToken));
            idsArray[j++] = keccak256(
                abi.encode(
                    "collateral", collateralToken, obligation.collaterals[i].oracle, obligation.collaterals[i].lltv
                )
            );
        }
        for (uint256 i = 0; i < MAX_DURATIONS; i++) {
            uint256 duration = localDurations[i];
            if (duration != 0) {
                idsArray[j++] = keccak256(abi.encode("duration", duration));
            }
        }
        return idsArray;
    }

    function updateDurations(uint256 maturityTime, Maturity storage maturity) internal returns (bytes32[] memory) {
        uint32[8] memory localDurations = maturity.durations;

        uint256 zeroedDurationsCount = 0;
        for (uint256 i = 0; i < MAX_DURATIONS; i++) {
            uint256 duration = localDurations[i];
            if (duration != 0 && duration > maturityTime) {
                zeroedDurationsCount++;
            }
        }

        bytes32[] memory zeroedDurationsIds = new bytes32[](zeroedDurationsCount);
        uint256 j = 0;
        for (uint256 i = 0; i < MAX_DURATIONS; i++) {
            uint256 duration = localDurations[i];
            if (duration != 0 && duration > maturityTime) {
                localDurations[i] = 0;
                zeroedDurationsIds[j++] = keccak256(abi.encode("duration", duration));
            }
        }

        maturity.durations = localDurations;

        return zeroedDurationsIds;
    }

    function selfDeallocate(bytes32[] memory changedIds, uint256 removed, uint256 assets) internal {
        IVaultV2(parentVault).deallocate(address(this), abi.encode(changedIds, -removed.toInt256()), assets);
    }

    /* TO REMOVE */

    function onLiquidate(Seizure[] memory, address, address, bytes memory) external pure {
        revert();
    }
}
