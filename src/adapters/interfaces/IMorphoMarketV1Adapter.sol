// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Morpho Association
pragma solidity >=0.5.0;

import {IAdapter} from "../../interfaces/IAdapter.sol";
import {Id, MarketParams} from "../../../lib/morpho-blue/src/interfaces/IMorpho.sol";

interface IMorphoMarketV1Adapter is IAdapter {
    /* EVENTS */

    event Allocate(uint256 mintedShares);
    event Deallocate(uint256 burnedShares);
    event ForceRemove();
    event RevokeForceRemove();
    event SetSkimRecipient(address indexed newSkimRecipient);
    event Skim(address indexed token, uint256 assets);
    event SubmitForceRemove(uint256 executableAt);
    /* ERRORS */

    error AlreadyPending();
    error InvalidData();
    error LoanAssetMismatch();
    error NotAuthorized();
    error NotPending();
    error NotTimelocked();
    error TimelockNotExpired();

    /* FUNCTIONS */

    function factory() external view returns (address);
    function parentVault() external view returns (address);
    function morpho() external view returns (address);
    function adapterId() external view returns (bytes32);
    function marketParams() external view returns (MarketParams memory);
    function collateralTokenId() external view returns (bytes32);
    function skimRecipient() external view returns (address);
    function supplyShares() external view returns (uint128);
    function allocation() external view returns (uint128);
    function ids() external view returns (bytes32[] memory);
    function setSkimRecipient(address newSkimRecipient) external;
    function skim(address token) external;
    function forceRemoveExecutableAt() external view returns (uint256);
    function submitForceRemove() external;
    function revokeForceRemove() external;
    function forceRemove() external;
}
