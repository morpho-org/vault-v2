// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Morpho Association
pragma solidity >= 0.5.0;

import {IAdapter} from "../../interfaces/IAdapter.sol";

interface IMorphoVaultV1Adapter is IAdapter {
    /* EVENTS */

    event SetSkimRecipient(address indexed newSkimRecipient);
    event Skim(address indexed token, uint256 assets);

    /* ERRORS */

    error AssetMismatch();
    error CannotSkimMorphoVaultV1Shares();
    error InvalidData();
    error NotAuthorized();

    /* FUNCTIONS */

    function factory() external view returns (address);
    function parentVault() external view returns (address);
    function morphoVaultV1() external view returns (address);
    function adapterId() external view returns (bytes32);
    function skimRecipient() external view returns (address);
    function allocation() external view returns (uint256);
    function ids() external view returns (bytes32[] memory);
    function setSkimRecipient(address newSkimRecipient) external;
    function skim(address token) external;
}
