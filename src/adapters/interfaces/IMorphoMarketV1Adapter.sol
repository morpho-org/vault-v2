// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Morpho Association
pragma solidity >=0.5.0;

import {IAdapter} from "../../interfaces/IAdapter.sol";
import {MarketParams} from "../../../lib/morpho-blue/src/interfaces/IMorpho.sol";

struct MarketPosition {
    uint128 supplyShares;
    uint128 allocation;
}

interface IMorphoMarketV1Adapter is IAdapter {
    /* EVENTS */

    event SetSkimRecipient(address indexed newSkimRecipient);
    event Skim(address indexed token, uint256 assets);
    event SubmitBurnShares(bytes32 indexed id, uint256 executableAt);
    event RevokeBurnShares(bytes32 indexed id);
    event BurnShares(bytes32 indexed id, uint256 supplyShares);
    event Allocate(bytes32 indexed marketId, uint256 newAllocation, uint256 shares);
    event Deallocate(bytes32 indexed marketId, uint256 newAllocation, uint256 shares);

    /* ERRORS */

    error AlreadyPending();
    error IrmMismatch();
    error LoanAssetMismatch();
    error NotAuthorized();
    error NotPending();
    error NotTimelocked();
    error SharePriceAboveOne();
    error TimelockNotExpired();

    /* FUNCTIONS */

    function factory() external view returns (address);
    function parentVault() external view returns (address);
    function asset() external view returns (address);
    function morpho() external view returns (address);
    function marketIds(uint256 index) external view returns (bytes32);
    function positions(bytes32 marketId) external view returns (uint128 supplyShares, uint128 allocation);
    function adapterId() external view returns (bytes32);
    function skimRecipient() external view returns (address);
    function marketIdsLength() external view returns (uint256);
    function newAllocation(bytes32 marketId) external view returns (uint256);
    function burnSharesExecutableAt(bytes32 id) external view returns (uint256);
    function ids(MarketParams memory marketParams) external view returns (bytes32[] memory);

    function submitBurnShares(bytes32 id) external;
    function revokeBurnShares(bytes32 id) external;
    function burnShares(bytes32 id) external;
    function setSkimRecipient(address newSkimRecipient) external;
    function skim(address token) external;
}
