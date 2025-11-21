// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Morpho Association
pragma solidity >=0.5.0;

import {IAdapter} from "../../interfaces/IAdapter.sol";
import {Id, MarketParams} from "../../../lib/morpho-blue/src/interfaces/IMorpho.sol";

struct MarketPosition {
    uint128 supplyShares;
    uint128 allocation;
}

/// @dev This interface is used for factorizing IMorphoMarketV1AdapterStaticTyping and IMorphoMarketV1Adapter.
/// @dev Consider using the IMorphoMarketV1Adapter interface instead of this one.
interface IMorphoMarketV1AdapterBase is IAdapter {
    /* EVENTS */

    event Allocate(MarketParams indexed marketParams, uint256 newAllocation, uint256 shares);
    event Deallocate(MarketParams indexed marketParams, uint256 newAllocation, uint256 shares);
    event SetSkimRecipient(address indexed newSkimRecipient);
    event Skim(address indexed token, uint256 assets);
    event SubmitBurnShares(Id indexed id, uint256 executableAt);
    event RevokeBurnShares(Id indexed id);
    event BurnShares(Id indexed id);

    /* ERRORS */

    error AlreadyPending();
    error LoanAssetMismatch();
    error NotAuthorized();
    error NotPending();
    error NotTimelocked();
    error SharePriceTooHigh();
    error TimelockNotExpired();

    /* FUNCTIONS */

    function factory() external view returns (address);
    function parentVault() external view returns (address);
    function asset() external view returns (address);
    function morpho() external view returns (address);
    function positions(Id id) external view returns (uint128 supplyShares, uint128 allocation);
    function adapterId() external view returns (bytes32);
    function skimRecipient() external view returns (address);
    function marketParamsListLength() external view returns (uint256);
    function submitBurnShares(Id id) external;
    function revokeBurnShares(Id id) external;
    function burnShares(Id id) external;
    function newAllocation(MarketParams memory marketParams) external view returns (uint256);
    function ids(MarketParams memory marketParams) external view returns (bytes32[] memory);
    function setSkimRecipient(address newSkimRecipient) external;
    function skim(address token) external;
}

/// @dev This interface is inherited by MorphoMarketV1Adapter so that function signatures are checked by the compiler.
/// @dev Consider using the IMorphoMarketV1Adapter interface instead of this one.
interface IMorphoMarketV1AdapterStaticTyping is IMorphoMarketV1AdapterBase {
    function marketParamsList(uint256 index) external view returns (address, address, address, address, uint256);
}

/// @dev Use this interface for MorphoMarketV1Adapter to have access to all the functions with the appropriate function
/// signatures.
interface IMorphoMarketV1Adapter is IMorphoMarketV1AdapterBase {
    function marketParamsList(uint256 index) external view returns (address, address, address, address, uint256);
}
