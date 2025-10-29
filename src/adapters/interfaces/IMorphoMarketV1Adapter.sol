// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Morpho Association
pragma solidity >=0.5.0;

import {IAdapter} from "../../interfaces/IAdapter.sol";
import {Id, MarketParams} from "../../../lib/morpho-blue/src/interfaces/IMorpho.sol";

/// @dev This interface is inherited by MorphoMarketV1Adapter so that function signatures are checked by the compiler.
/// @dev Consider using the IMorphoMarketV1AdapterReturnsStruct interface instead.
interface IMorphoMarketV1Adapter is IAdapter {
    /* EVENTS */

    event SetSkimRecipient(address indexed newSkimRecipient);
    event Skim(address indexed token, uint256 assets);

    /* ERRORS */

    error LoanAssetMismatch();
    error NotAuthorized();

    /* FUNCTIONS */

    function factory() external view returns (address);
    function parentVault() external view returns (address);
    function asset() external view returns (address);
    function morpho() external view returns (address);
    function adapterId() external view returns (bytes32);
    function skimRecipient() external view returns (address);
    function marketParamsList(uint256 index) external view returns (address, address, address, address, uint256);
    function marketParamsListLength() external view returns (uint256);
    function allocation(MarketParams memory marketParams) external view returns (uint256);
    function ids(MarketParams memory marketParams) external view returns (bytes32[] memory);
    function setSkimRecipient(address newSkimRecipient) external;
    function skim(address token) external;
}

/// @dev Use this interface to have access to all the functions with the appropriate function signatures.
interface IMorphoMarketV1AdapterReturnsStruct is IAdapter {
    /* EVENTS */

    event SetSkimRecipient(address indexed newSkimRecipient);
    event Skim(address indexed token, uint256 assets);

    /* ERRORS */

    error LoanAssetMismatch();
    error NotAuthorized();

    /* FUNCTIONS */

    function factory() external view returns (address);
    function parentVault() external view returns (address);
    function asset() external view returns (address);
    function morpho() external view returns (address);
    function adapterId() external view returns (bytes32);
    function skimRecipient() external view returns (address);
    function marketParamsList(uint256 index) external view returns (MarketParams memory);
    function marketParamsListLength() external view returns (uint256);
    function allocation(MarketParams memory marketParams) external view returns (uint256);
    function ids(MarketParams memory marketParams) external view returns (bytes32[] memory);
    function setSkimRecipient(address newSkimRecipient) external;
    function skim(address token) external;
}
