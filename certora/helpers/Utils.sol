// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.28;

contract Utils {
    function toBytes4(bytes memory data) public pure returns (bytes4) {
        return bytes4(data);
    }
}
