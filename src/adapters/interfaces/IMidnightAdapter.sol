// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Morpho Association
pragma solidity >=0.5.0;

import {IAdapter} from "../../interfaces/IAdapter.sol";
import {Market} from "lib/midnight/src/interfaces/IMidnight.sol";
import {IBuyCallback, ISellCallback} from "lib/midnight/src/interfaces/ICallbacks.sol";
import {IRatifier} from "lib/midnight/src/interfaces/IRatifier.sol";

// Chain of maturities, each can represent multiple markets.
// nextMaturity is 0 if no next maturity.
struct MaturityData {
    uint128 netCredit;
    uint128 growth;
    uint48 prevMaturity;
    uint48 nextMaturity;
    uint8 durationCount;
}

interface IMidnightAdapter is IAdapter, IBuyCallback, ISellCallback, IRatifier {
    /* EVENTS */

    event SetSkimRecipient(address indexed newSkimRecipient);
    event Skim(address indexed token, uint256 assets);
    event WithdrawToVault(bytes32 indexed marketId, uint256 withdrawnAssets, uint256 netCreditDecrease);
    event UpdateDurationCountAndAllocations(uint256 indexed maturity, uint256 newDurationCount, uint256 netCredit);
    event ForceDeallocate(bytes32 indexed marketId, uint256 sellerAssets, uint256 netCreditDecrease);
    event Buy(bytes32 indexed marketId, uint256 paidAssets, uint256 netCreditIncrease, int256 change);
    event Sell(bytes32 indexed marketId, uint256 sellerAssets, uint256 netCreditDecrease);
    event AccrueInterest(uint128 currentGrowth, uint256 totalAssets);
    event RemoveMaturity(uint256 indexed maturity);
    event InsertMaturity(uint256 indexed maturity);

    /* ERRORS */

    error BufferTooLow();
    error BuyAtLoss();
    error IncorrectCallbackAddress();
    error IncorrectDuration();
    error IncorrectOffer();
    error IncorrectOwner();
    error IncorrectSigner();
    error IncorrectStart();
    error InvalidProof();
    error LoanAssetMismatch();
    error NoBorrowing();
    error NoDebtCreation();
    error NotAuthorized();
    error NotMidnight();
    error NotSelf();
    error SelfAllocationOnly();

    /* FUNCTIONS */

    function asset() external view returns (address);
    function totalAssets() external view returns (uint128);
    function lastUpdate() external view returns (uint48);
    function currentGrowth() external view returns (uint128);
    function availableMaturities() external view returns (uint8);
    function midnight() external view returns (address);
    function adapterId() external view returns (bytes32);
    function packedDurations() external view returns (bytes32);
    function netCredit(bytes32 marketId) external view returns (uint256);
    function maturities(uint256 date) external view returns (MaturityData memory);
    function skimRecipient() external view returns (address);
    function setSkimRecipient(address newSkimRecipient) external;
    function skim(address token) external;
    function durations() external view returns (uint256[] memory);
    function durationsLength() external view returns (uint256);
    function updateDurationCountAndAllocations(Market memory market) external;
    function withdrawToVault(Market memory market, uint256 units) external;
    function ids(Market memory market) external view returns (bytes32[] memory);
    function parentVault() external view returns (address);
    function accrueInterestView() external view returns (uint48, uint128, uint128, uint256);
    function accrueInterest() external returns (uint48, uint128, uint256);
    function allocate(bytes memory data, uint256 assets, bytes4, address vaultAllocator)
        external
        returns (bytes32[] memory, int256);
    function deallocate(bytes memory data, uint256 assets, bytes4, address vaultAllocator)
        external
        returns (bytes32[] memory, int256);
    function onBuy(
        bytes32 id,
        Market memory market,
        uint256 buyerAssets,
        uint256 units,
        uint256 pendingFeeIncrease,
        address buyer,
        bytes memory data
    ) external returns (bytes32);
    function onSell(
        bytes32 id,
        Market memory market,
        uint256 sellerAssets,
        uint256 units,
        uint256 pendingFeeDecrease,
        address seller,
        address receiver,
        bytes memory data
    ) external returns (bytes32);
}
