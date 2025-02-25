// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import {VaultV2} from "../VaultV2.sol";

library EncodeLib {
    function reallocateToIdleCall(address market, uint256 amount) internal pure returns (bytes memory) {
        return abi.encodeCall(VaultV2.reallocateToIdle, (market, amount));
    }

    function reallocateFromIdleCall(address market, uint256 amount) internal pure returns (bytes memory) {
        return abi.encodeCall(VaultV2.reallocateFromIdle, (market, amount));
    }
}
