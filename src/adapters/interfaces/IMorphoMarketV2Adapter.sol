// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Morpho Association
pragma solidity >=0.5.0;

import {IAdapter} from "../../interfaces/IAdapter.sol";
import {Obligation, Seizure} from "lib/morpho-v2/src/interfaces/IMorphoV2.sol";
import {ICallbacks} from "lib/morpho-v2/src/interfaces/ICallbacks.sol";

// Chain of maturities, each can represent multiple obligations.
// nextMaturity is type(uint48).max if no next maturity
struct MaturityData {
    uint128 units;
    uint128 growth;
    uint48 nextMaturity;
    uint48 lastUpdate;
}

interface IMorphoMarketV2Adapter is IAdapter, ICallbacks {
    /* EVENTS */

    event SetSkimRecipient(address indexed newSkimRecipient);
    event Skim(address indexed token, uint256 assets);
    event AddDuration(uint256 duration);
    event RemoveDuration(uint256 duration);

    /* ERRORS */

    error BufferTooLow();
    error DurationAlreadyExists();
    error IncorrectCallbackAddress();
    error IncorrectCallbackData();
    error IncorrectCollateralSet();
    error IncorrectDuration();
    error IncorrectExpiry();
    error IncorrectHint();
    error IncorrectMaturity();
    error IncorrectMinTimeToMaturity();
    error IncorrectOffer();
    error IncorrectOwner();
    error IncorrectProof();
    error IncorrectSignature();
    error IncorrectSigner();
    error IncorrectStart();
    error IncorrectUnits();
    error LoanAssetMismatch();
    error NoBorrowing();
    error NotAuthorized();
    error NotMorphoV2();
    error NotSelf();
    error PriceBelowOne();
    error SelfAllocationOnly();
    error TooManyDurations();

    /* FUNCTIONS */

    function _totalAssets() external view returns (uint256);
    function lastUpdate() external view returns (uint48);
    function firstMaturity() external view returns (uint48);
    function currentGrowth() external view returns (uint128);
    function adapterId() external view returns (bytes32);
    function units(bytes32 obligationId) external view returns (uint256);
    function maturities(uint256 date) external view returns (MaturityData memory);
    function setSkimRecipient(address newSkimRecipient) external;
    function skim(address token) external;
    function durations() external view returns (uint256[] memory);
    function durationsLength() external view returns (uint256);
    function deallocateExpiredDurations(Obligation memory obligation) external;
    function withdraw(Obligation memory obligation, uint256 units, uint256 shares) external;
    function ids(Obligation memory obligation) external view returns (bytes32[] memory);
    function parentVault() external view returns (address);
    function accrueInterestView() external view returns (uint48, uint128, uint256);
    function accrueInterest() external;
    function realizeLoss(Obligation memory obligation) external;
    function allocate(bytes memory data, uint256 assets, bytes4, address vaultAllocator)
        external
        returns (bytes32[] memory, int256);
    function deallocate(bytes memory data, uint256 assets, bytes4, address vaultAllocator)
        external
        returns (bytes32[] memory, int256);
    function onBuy(
        Obligation memory obligation,
        address buyer,
        uint256 buyerAssets,
        uint256 sellerAssets,
        uint256 obligationUnits,
        uint256 obligationShares,
        bytes memory data
    ) external;
    function onSell(
        Obligation memory obligation,
        address seller,
        uint256 buyerAssets,
        uint256 sellerAssets,
        uint256 obligationUnits,
        uint256 obligationShares,
        bytes memory data
    ) external;
    function onLiquidate(Seizure[] memory seizures, address borrower, address liquidator, bytes memory data) external;
}
