// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Morpho Association
pragma solidity >=0.5.0;

import {IAdapter} from "../../interfaces/IAdapter.sol";
// import {Id, MarketParams} from "../../../lib/morpho-blue/src/interfaces/IMorpho.sol";
import {Offer, Signature, Obligation, Collateral, Seizure} from "lib/morpho-v2/src/interfaces/IMorphoV2.sol";
import {ICallbacks} from "lib/morpho-v2/src/interfaces/ICallbacks.sol";

// Position in an obligation
struct ObligationPosition {
    uint128 units;
    uint128 growth;
}

// Chain of maturities, each can represent multiple obligations.
// nextMaturity is type(uint48).max if no next maturity
struct Maturity {
    uint128 growthLostAtMaturity;
    uint48 nextMaturity;
}

interface IMorphoMarketV2Adapter is IAdapter, ICallbacks {
    /* EVENTS */

    event SetSkimRecipient(address indexed newSkimRecipient);
    event Skim(address indexed token, uint256 assets);

    /* ERRORS */

    error BelowMinRate();
    error BufferTooLow();
    error IncorrectCallbackAddress();
    error IncorrectCallbackData();
    error IncorrectCollateralSet();
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

    /* FUNCTIONS */

    function _totalAssets() external view returns (uint256);
    function lastUpdate() external view returns (uint48);
    function firstMaturity() external view returns (uint48);
    function currentGrowth() external view returns (uint128);
    function positions(bytes32 obligationId) external view returns (ObligationPosition memory);
    function maturities(uint256 date) external view returns (Maturity memory);
    function setSkimRecipient(address newSkimRecipient) external;
    function skim(address token) external;
    function setMinTimeToMaturity(uint256 minTimeToMaturity) external;
    function withdraw(Obligation memory obligation, uint256 units, uint256 shares) external;
    function minTimeToMaturity() external view returns (uint256);
    function minRate() external view returns (uint256);
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
