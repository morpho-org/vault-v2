// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Morpho Association
pragma solidity >=0.5.0;

import {IAdapter} from "../../interfaces/IAdapter.sol";
import {Id, MarketParams} from "../../../lib/morpho-blue-irm/lib/morpho-blue/src/interfaces/IMorpho.sol";

struct MarketPosition {
    uint128 supplyShares;
    uint128 allocation;
}

interface IMorphoMarketV1Adapter is IAdapter {
    /* EVENTS */

    event Allocate(MarketParams indexed marketParams, uint256 newAllocation, uint256 shares);
    event Deallocate(MarketParams indexed marketParams, uint256 newAllocation, uint256 shares);
    event SetSkimRecipient(address indexed newSkimRecipient);
    event Skim(address indexed token, uint256 assets);
    event SubmitBurnShares(MarketParams indexed marketParams, uint256 executableAt);
    event RevokeBurnShares(MarketParams indexed marketParams);
    event BurnShares(MarketParams indexed marketParams);

    /* ERRORS */

    error IrmMismatch();
    error LoanAssetMismatch();
    error NotAuthorized();
    error NotTimelocked();
    error TimelockNotExpired();
    error AlreadyPending();
    error NotPending();

    /* FUNCTIONS */

    function factory() external view returns (address);
    function parentVault() external view returns (address);
    function asset() external view returns (address);
    function morpho() external view returns (address);
    function marketIds(uint256 index) external view returns (Id);
    function positions(Id marketId) external view returns (uint128, uint128);
    function adapterId() external view returns (bytes32);
    function skimRecipient() external view returns (address);
    function marketIdsLength() external view returns (uint256);
    function submitBurnShares(MarketParams memory marketParams) external;
    function burnShares(MarketParams memory marketParams) external;
    function ids(MarketParams memory marketParams) external view returns (bytes32[] memory);
    function setSkimRecipient(address newSkimRecipient) external;
    function skim(address token) external;
}
