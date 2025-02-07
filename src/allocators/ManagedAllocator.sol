// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.27;

import {BaseAllocator} from "./BaseAllocator.sol";

// This allocator makes an account completely manage the allocation of the vault.
contract ManagedAllocator is BaseAllocator {
    address public immutable owner;

    constructor(address _owner) {
        owner = _owner;
    }

    function authorizeMulticall(address sender, bytes[] calldata) external view override {
        require(sender == owner);
    }
}
