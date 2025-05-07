// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import {ManualInterestController} from "../../ManualInterestController.sol";

library ManualInterestControllerAddressLib {
    function computeManualInterestControllerAddress(address factory, address owner, bytes32 salt)
        internal
        pure
        returns (address)
    {
        bytes32 initCodeHash =
            keccak256(abi.encodePacked(type(ManualInterestController).creationCode, abi.encode(owner)));
        return address(uint160(uint256(keccak256(abi.encodePacked(uint8(0xff), factory, salt, initCodeHash)))));
    }
}
