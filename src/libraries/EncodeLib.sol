// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import {IIRM} from "../interfaces/IIRM.sol";
import {VaultsV2} from "../VaultsV2.sol";

library EncodeLib {
    function setIRMCall(address irm) internal pure returns (bytes memory) {
        return abi.encodeWithSelector(VaultsV2.setIRM.selector, address(irm));
    }
}
