// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import {VaultsV2} from "../VaultsV2.sol";

library EncodeLib {
    function reallocateToIdleCall(uint256 marketIndex, uint256 amount) internal pure returns (bytes memory) {
        return abi.encodeCall(VaultsV2.reallocateToIdle, (marketIndex, amount));
    }

    function reallocateFromIdleCall(uint256 marketIndex, uint256 amount) internal pure returns (bytes memory) {
        return abi.encodeCall(VaultsV2.reallocateFromIdle, (marketIndex, amount));
    }
}
