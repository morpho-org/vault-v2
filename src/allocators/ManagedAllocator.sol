// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.28;

import {BaseAllocator} from "./BaseAllocator.sol";
import {ErrorsLib} from "../libraries/ErrorsLib.sol";

// This allocator makes an account completely manage the allocation of the vault.
contract ManagedAllocator is BaseAllocator {
    address public immutable owner;

    constructor(address _owner) {
        owner = _owner;
    }

    function authorizeMulticall(address sender, bytes[] calldata) external view override {
        require(sender == owner, ErrorsLib.Unauthorized());
    }
}
