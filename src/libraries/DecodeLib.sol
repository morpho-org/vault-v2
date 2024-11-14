// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import {VaultsV2} from "../VaultsV2.sol";

library DecodeLib {
    function getSelector(bytes memory call) internal pure returns (bytes4) {
        return bytes4(call);
    }
}
