// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.27;

import {IAllocator} from "../interfaces/IAllocator.sol";
import {VaultsV2} from "../VaultsV2.sol";

abstract contract BaseAllocator is IAllocator {
    function authorizeMulticall(address sender, bytes[] calldata bundle) external view virtual;
}
