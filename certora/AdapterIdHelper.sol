// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.28;

contract AdapterIdHelper {
    function adapterId(address adapter) external pure returns (bytes32) {
        return keccak256(bytes.concat(bytes32("Adapter ID"),bytes32(uint(uint160(adapter)))));
    }
}
