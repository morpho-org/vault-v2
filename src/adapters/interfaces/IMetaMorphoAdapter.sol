// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity >= 0.5.0;

import {IAdapter} from "../../interfaces/IAdapter.sol";

interface IMetaMorphoAdapter is IAdapter {
    /* EVENTS */

    event SetSkimRecipient(address indexed newSkimRecipient);
    event Skim(address indexed token, uint256 assets);

    /* ERRORS */

    error NotAuthorized();
    error InvalidData();
    error CannotSkimMetaMorphoShares();
    error AssetMismatch();
    error MaxSlippageExceeded();

    /* FUNCTIONS */

    function setSkimRecipient(address newSkimRecipient) external;
    function skim(address token) external;
    function parentVault() external view returns (address);
    function metaMorpho() external view returns (address);
    function skimRecipient() external view returns (address);
}
