// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import {ErrorsLib} from "./ErrorsLib.sol";

library UtilsLib {
    /// @dev Returns the first word returned by a successful static call.
    /// @dev Returns 0 if no data was returned or if the static call reverted.
    /// @dev Unlike a low-level solidity call, does not copy all the return data to memory.
    function controlledStaticCall(address to, bytes memory data) private view returns (bytes32 res) {
        assembly ("memory-safe") {
            let success := staticcall(gas(), to, add(data, 32), mload(data), 0, 32)
            res := mul(success, mload(0))
        }
    }

    function controlledStaticCallUint(address to, bytes memory data) internal view returns (uint256) {
        return uint256(controlledStaticCall(to, data));
    }

    /// @dev Returns true iff the first word returned by a successful static call was exactly 1.
    /// @dev Note that the behaviour is non standard: if the call returned a value >1, it returns false.
    function controlledStaticCallBool(address to, bytes memory data) internal view returns (bool) {
        return controlledStaticCall(to, data) == bytes32(uint256(1));
    }
}
