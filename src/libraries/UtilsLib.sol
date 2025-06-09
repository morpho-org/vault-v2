// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import {ErrorsLib} from "./ErrorsLib.sol";

library UtilsLib {
    /// @dev Returns the word returned by a successful static call.
    /// @dev Reverts if the static call reverted with no data.
    /// @dev Returns 0 if the static call reverted with data.
    /// @dev Returns 0 if the returned data is not exactly 32 bytes long.
    /// @dev Unlike a low-level solidity call, does not copy all the return data to memory.
    function controlledStaticCall(address to, bytes memory data) internal view returns (uint256) {
        uint256[1] memory output;
        bool success;
        uint256 returnDataSize;
        assembly ("memory-safe") {
            success := staticcall(gas(), to, add(data, 32), mload(data), output, 32)
            returnDataSize := returndatasize()
        }
        // Do not handle low-level reverts such as OOG.
        require(success || returnDataSize > 0, ErrorsLib.StaticCallRevertedWithoutData());
        if (success && returnDataSize == 32) return output[0];
        else return 0;
    }
}
