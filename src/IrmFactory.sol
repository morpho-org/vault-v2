// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.28;

import {IIrmFactory} from "./interfaces/IIRMFactory.sol";

import {IRM} from "./IRM.sol";

contract IrmFactory is IIrmFactory {
    mapping(address => bool) public isIrm;

    event CreateIrm(address indexed irm, address indexed owner);

    function createIrm(address owner, bytes32 salt) external returns (address) {
        address irm = address(new IRM{salt: salt}(owner));

        isIrm[irm] = true;
        emit CreateIrm(irm, owner);

        return irm;
    }
}
