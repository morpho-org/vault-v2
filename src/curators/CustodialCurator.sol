// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.27;

import {ICurator} from "../interfaces/ICurator.sol";

// This curator completely controls the assets of the vault.
contract CustodialCurator is ICurator {
    address public immutable owner;

    constructor(address _owner) {
        owner = _owner;
    }

    function authorizeMulticall(address sender, bytes[] calldata) external view {
        require(sender == owner);
    }
}
