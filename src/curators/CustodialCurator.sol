// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.27;

import {BaseCurator} from "./BaseCurator.sol";

// This curator completely controls the assets of the vault.
contract CustodialCurator is BaseCurator {
    address public immutable owner;

    constructor(address _owner) {
        owner = _owner;
    }

    function authorizeMulticall(address sender, bytes[] calldata) external view override {
        require(sender == owner);
    }
}
