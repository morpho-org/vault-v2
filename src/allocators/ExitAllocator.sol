// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.27;

import {BaseAllocator} from "./BaseAllocator.sol";
import {VaultsV2} from "../VaultsV2.sol";
import {DecodeLib} from "../libraries/DecodeLib.sol";

// This allocator allows reallocation to idle.
// It can be useful if the curator notices that the allocator is preventing users from withdrawing.
contract ExitAllocator is BaseAllocator {
    using DecodeLib for bytes;

    function authorizeMulticall(address, bytes[] calldata bundle) external pure override {
        for (uint256 i; i < bundle.length; i++) {
            require(bundle[i].selector_() != VaultsV2.reallocateFromIdle.selector);
        }
    }
}
