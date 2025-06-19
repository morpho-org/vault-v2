// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Morpho Association
pragma solidity >= 0.5.0;

import {IAdapter} from "../../interfaces/IAdapter.sol";

interface IMetaMorphoAdapter is IAdapter {
    /* EVENTS */

    event SetSkimRecipient(address indexed newSkimRecipient);
    event Skim(address indexed token, uint256 assets);

    /* ERRORS */

    error AssetMismatch();
    error CannotSkimMetaMorphoShares();
    error InvalidData();
    error NoLoss();
    error NotAuthorized();

    /* FUNCTIONS */

    function factory() external view returns (address);
    function setSkimRecipient(address newSkimRecipient) external;
    function skim(address token) external;
    function parentVault() external view returns (address);
    function metaMorpho() external view returns (address);
    function skimRecipient() external view returns (address);
    function trackedAllocation() external view returns (uint256);
    function shares() external view returns (uint256);
}
