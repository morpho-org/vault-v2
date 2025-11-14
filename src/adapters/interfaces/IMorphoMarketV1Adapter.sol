// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Morpho Association
pragma solidity >=0.5.0;

import {IAdapter} from "../../interfaces/IAdapter.sol";
import {Id, MarketParams} from "../../../lib/morpho-blue/src/interfaces/IMorpho.sol";

interface IMorphoMarketV1Adapter is IAdapter {
    /* EVENTS */

    event SetSkimRecipient(address indexed newSkimRecipient);
    event Skim(address indexed token, uint256 assets);
    event SubmitBurnShares(MarketParams indexed marketParams, uint256 executableAt);
    event RevokeBurnShares(MarketParams indexed marketParams);
    event BurnShares(MarketParams indexed marketParams, uint256 shares);
    event Allocate(MarketParams indexed marketParams, uint256 shares);
    event Deallocate(MarketParams indexed marketParams, uint256 shares);
    event UpdateList(MarketParams[] marketParamsList);
    /* ERRORS */

    error LoanAssetMismatch();
    error NotAuthorized();
    error NotTimelocked();
    error TimelockNotExpired();
    error AlreadyPending();

    /* FUNCTIONS */

    function factory() external view returns (address);
    function parentVault() external view returns (address);
    function asset() external view returns (address);
    function morpho() external view returns (address);
    function adapterId() external view returns (bytes32);
    function skimRecipient() external view returns (address);
    function marketParamsList(uint256 index) external view returns (address, address, address, address, uint256);
    function marketParamsListLength() external view returns (uint256);
    function submitBurnShares(MarketParams memory marketParams) external;
    function burnShares(MarketParams memory marketParams) external;
    function oldAllocation(MarketParams memory marketParams) external view returns (uint256);
    function newAllocation(MarketParams memory marketParams) external view returns (uint256);
    function ids(MarketParams memory marketParams) external view returns (bytes32[] memory);
    function setSkimRecipient(address newSkimRecipient) external;
    function skim(address token) external;
}
