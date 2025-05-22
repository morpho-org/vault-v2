// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import {ErrorsLib} from "./ErrorsLib.sol";

library UtilsLib {
    /// @dev Returns the first word returned by a successful static call.
    /// @dev Returns 0 if no data was returned.
    /// @dev Returns 0 if the static call reverted.
    function controlledStaticCall(address to, bytes memory data) internal view returns (uint256) {
        uint256[1] memory output;
        bool success;
        assembly ("memory-safe") {
            success := staticcall(gas(), to, add(data, 32), mload(data), output, 32)
        }
        if (success) {
            return output[0];
        } else {
            return 0;
        }
    }
}
