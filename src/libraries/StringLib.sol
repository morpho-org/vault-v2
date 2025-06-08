// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

library StringLib {
    function writeStringToSlot(string memory str, uint256 slot) internal {
        uint256 len = bytes(str).length;
        bytes32 mask;
        require(len <= 31);
        assembly {
            let value := mload(add(32, str))

            // Clean the bytes at the right, but maybe not useful as this should be enforced by solidity.
            mask := sub(shl(mul(8, sub(32, len)), 1), 1)
            let strData := and(value, mask)
            let encoded := or(value, mul(len, 2))
            sstore(slot, encoded)
        }
    }

    function readStringFromSlot(uint256 slot) internal view returns (string memory str) {
        assembly {
            let encoded := sload(slot)
            let len := div(and(0xff, encoded), 2)
            let strData := and(encoded, not(0xff))

            let ptr := mload(0x40)
            mstore(ptr, len)
            mstore(add(ptr, 32), strData)
            mstore(0x40, add(ptr, 64))

            str := ptr
        }
    }
}
