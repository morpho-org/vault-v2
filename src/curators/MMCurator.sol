// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.27;

import {ICurator} from "../interfaces/ICurator.sol";
import {VaultsV2} from "../VaultsV2.sol";
import "../libraries/DecodeLib.sol";

contract MMCurator is ICurator {
    using DecodeLib for bytes;

    address public immutable owner;

    constructor(address _owner) {
        owner = _owner;
    }

    mapping(address => bool) public isAllocator;

    function setAllocator(address allocator, bool enabled) public {
        require(msg.sender == owner);
        isAllocator[allocator] = enabled;
    }

    function authorizeMulticall(address sender, bytes[] calldata bundle) external view {
        if (sender == owner) return;
        if (isAllocator[sender]) {
            require(bundle.length == 2);
            ReallocateToIdleData memory toIdle = bundle[0].decodeAsReallocateToIdleData();
            ReallocateFromIdleData memory fromIdle = bundle[1].decodeAsReallocateFromIdleData();
            require(toIdle.amount == fromIdle.amount);
        }
    }
}
