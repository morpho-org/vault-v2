// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.28;

import {IVaultV2} from "../../src/interfaces/IVaultV2.sol";

contract Utils {
    function toBytes4(bytes memory data) public pure returns (bytes4) {
        return bytes4(data);
    }

    function encodeSetIsAllocatorCall(uint32 selector, address account, bool newIsAllocator)
        public
        pure
        returns (bytes memory)
    {
        return abi.encodePacked(selector, abi.encode(account, newIsAllocator));
    }
}
