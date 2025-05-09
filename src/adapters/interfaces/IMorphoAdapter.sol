// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.28;

import {MarketParams} from "../../../lib/morpho-blue/src/interfaces/IMorpho.sol";

interface IMorphoAdapter {
    /* EVENTS */

    event SetSkimRecipient(address indexed newSkimRecipient);
    event Skim(address indexed token, uint256 assets);

    /* ERRORS */

    error NotAuthorized();

    /* FUNCTIONS */

    function setSkimRecipient(address newSkimRecipient) external;

    function skim(address token) external;

    function allocate(bytes memory data, uint256 assets) external returns (bytes32[] memory);

    function deallocate(bytes memory data, uint256 assets) external returns (bytes32[] memory);

    function parentVault() external view returns (address);

    function morpho() external view returns (address);

    function skimRecipient() external view returns (address);
}
