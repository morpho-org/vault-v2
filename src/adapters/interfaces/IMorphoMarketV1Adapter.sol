// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Morpho Association
pragma solidity >=0.5.0;

import {IAdapter} from "../../interfaces/IAdapter.sol";
import {MarketParams} from "../../../lib/morpho-blue/src/interfaces/IMorpho.sol";

interface IMorphoMarketV1Adapter is IAdapter {
    /* EVENTS */

    event Submit(bytes4 indexed selector, bytes data, uint256 executableAt);
    event Revoke(address indexed sender, bytes4 indexed selector, bytes data);
    event Accept(bytes4 indexed selector, bytes data);
    event SetSkimRecipient(address indexed newSkimRecipient);
    event Skim(address indexed token, uint256 assets);
    event BurnShares(bytes32 indexed marketId, uint256 supplyShares);
    event Allocate(bytes32 indexed marketId, uint256 newAllocation, uint256 mintedShares);
    event Deallocate(bytes32 indexed marketId, uint256 newAllocation, uint256 burnedShares);

    /* ERRORS */

    error AlreadyPending();
    error DataNotTimelocked();
    error IrmMismatch();
    error LoanAssetMismatch();
    error SharePriceAboveOne();
    error TimelockNotExpired();
    error Unauthorized();

    /* VIEW FUNCTIONS */

    function factory() external view returns (address);
    function parentVault() external view returns (address);
    function asset() external view returns (address);
    function morpho() external view returns (address);
    function marketIds(uint256 index) external view returns (bytes32);
    function supplyShares(bytes32 marketId) external view returns (uint256);
    function adapterId() external view returns (bytes32);
    function skimRecipient() external view returns (address);
    function marketIdsLength() external view returns (uint256);
    function allocation(MarketParams memory marketParams) external view returns (uint256);
    function expectedSupplyAssets(bytes32 marketId) external view returns (uint256);
    function ids(MarketParams memory marketParams) external view returns (bytes32[] memory);
    function executableAt(bytes memory data) external view returns (uint256);

    /* NON-VIEW FUNCTIONS */

    function submit(bytes memory data) external;
    function revoke(bytes memory data) external;
    function morphoMarketV1AdapterV2SetSkimRecipient(address newSkimRecipient) external;
    function morphoMarketV1AdapterV2BurnShares(bytes32 marketId) external;
    function skim(address token) external;
}
