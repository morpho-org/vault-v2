// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Morpho Association
pragma solidity >=0.5.0;

import {IAdapter} from "../../interfaces/IAdapter.sol";
import {Obligation} from "lib/midnight/src/interfaces/IMidnight.sol";
import {ICallbacks} from "lib/midnight/src/interfaces/ICallbacks.sol";
import {IRatifier} from "lib/midnight/src/interfaces/IRatifier.sol";

// Chain of maturities, each can represent multiple obligations.
// nextMaturity is type(uint48).max if no next maturity
/// @dev vaultNetCredit is the net credit owned by the vault at that maturity.
struct MaturityData {
    uint128 vaultNetCredit;
    uint128 growth;
    uint48 nextMaturity;
    uint8 durationIndex;
}

// vaultNetCredit is the net credit owned by the vault in that obligation.
// userNetCredit is the net credit owned by the users in that obligation.
struct Position {
    uint128 vaultNetCredit;
    uint128 userNetCredit;
    uint128 userShares;
}

interface IMidnightAdapter is IAdapter, ICallbacks, IRatifier {
    /* EVENTS */

    event SetSkimRecipient(address indexed newSkimRecipient);
    event Skim(address indexed token, uint256 assets);

    /* ERRORS */

    error BufferTooLow();
    error BuyAtLoss();
    error IncorrectCallbackAddress();
    error IncorrectDuration();
    error IncorrectHint();
    error IncorrectMaturity();
    error IncorrectOffer();
    error IncorrectOwner();
    error IncorrectSigner();
    error IncorrectStart();
    error LoanAssetMismatch();
    error NoDebtCreation();
    error NotAuthorized();
    error NotMidnight();
    error NotSelf();
    error SelfAllocationOnly();

    /* FUNCTIONS */

    function asset() external view returns (address);
    function _totalAssets() external view returns (uint256);
    function lastUpdate() external view returns (uint48);
    function firstMaturity() external view returns (uint48);
    function currentGrowth() external view returns (uint128);
    function midnight() external view returns (address);
    function adapterId() external view returns (bytes32);
    function packedDurations() external view returns (bytes32);
    function positions(bytes32 obligationId)
        external
        view
        returns (uint128 vaultNetCredit, uint128 userNetCredit, uint128 userShares);
    function shares(bytes32 obligationId, address user) external view returns (uint256);
    function maturities(uint256 date) external view returns (MaturityData memory);
    function skimRecipient() external view returns (address);
    function setSkimRecipient(address newSkimRecipient) external;
    function skim(address token) external;
    function durations() external view returns (uint256[] memory);
    function durationsLength() external view returns (uint256);
    function updateDurationIndexAndAllocations(Obligation memory obligation) external;
    function withdrawToVault(Obligation memory obligation, uint256 withdrawnAssets) external;
    function withdrawShares(Obligation memory obligation, uint256 redeemedShares) external;
    function ids(Obligation memory obligation) external view returns (bytes32[] memory);
    function parentVault() external view returns (address);
    function accrueInterestView() external view returns (uint48, uint128, uint256);
    function accrueInterest() external returns (uint48, uint128, uint256);
    function allocate(bytes memory data, uint256 assets, bytes4, address vaultAllocator)
        external
        returns (bytes32[] memory, int256);
    function deallocate(bytes memory data, uint256 assets, bytes4, address vaultAllocator)
        external
        returns (bytes32[] memory, int256);
    function onBuy(
        bytes32 id,
        Obligation memory obligation,
        address buyer,
        uint256 buyerAssets,
        uint256 units,
        uint256 buyerPendingFeeIncrease,
        bytes memory data
    ) external returns (bytes32);
    function onSell(
        bytes32 id,
        Obligation memory obligation,
        address seller,
        uint256 sellerAssets,
        uint256 units,
        uint256 sellerPendingFeeDecrease,
        bytes memory data
    ) external returns (bytes32);
    function onLiquidate(
        bytes32 id,
        Obligation memory obligation,
        uint256 collateralIndex,
        uint256 seizedAssets,
        uint256 repaidUnits,
        address borrower,
        bytes memory data
    ) external;
    function onRepay(
        bytes32 obligationId,
        Obligation memory obligation,
        uint256 units,
        address onBehalf,
        bytes memory data
    ) external;
}
