// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity >=0.5.0;

import {MarketParams} from "../../../lib/morpho-blue/src/interfaces/IMorpho.sol";
import {IAdapter} from "../../interfaces/IAdapter.sol";

interface IMorphoAdapter is IAdapter {
    /* EVENTS */

    event SetSkimRecipient(address indexed newSkimRecipient);
    event Skim(address indexed token, uint256 assets);

    /* ERRORS */

    error NotAuthorized();
    error CannotRealizeAsMuch();

    /* FUNCTIONS */

    function setSkimRecipient(address newSkimRecipient) external;
    function skim(address token) external;
    function parentVault() external view returns (address);
    function morpho() external view returns (address);
    function skimRecipient() external view returns (address);
}
