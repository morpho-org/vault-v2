// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.28;

import {IAllocator} from "../interfaces/IAllocator.sol";
import {VaultV2} from "../VaultV2.sol";

abstract contract BaseAllocator is IAllocator {
    function authorizeMulticall(address sender, bytes[] calldata bundle) external view virtual;
}
