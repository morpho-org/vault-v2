// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.27;

import {ICurator} from "../interfaces/ICurator.sol";
import {VaultsV2} from "../VaultsV2.sol";
import {DecodeLib} from "../libraries/DecodeLib.sol";

contract MMCurator is ICurator {
    using DecodeLib for bytes;

    address public immutable owner;

    constructor(address _owner) {
        owner = _owner;
    }

    function authorizedMulticall(address sender, bytes[] calldata bundle) external view returns (bool) {
        if (sender == owner) return true;
        for (uint256 i = 0; i < bundle.length; i++) {
            if (restrictedFunction(bundle[i].getSelector())) return false;
        }
        return true;
    }

    function restrictedFunction(bytes4 selector) internal pure returns (bool) {
        return selector == VaultsV2.setIRM.selector || selector == VaultsV2.enableNewMarket.selector;
    }
}
