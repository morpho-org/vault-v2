// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Morpho Association
pragma solidity 0.8.37;

import {ForceDeallocationEnterGate} from "./ForceDeallocationEnterGate.sol";
import {IForceDeallocationEnterGateFactory} from "./interfaces/IForceDeallocationEnterGateFactory.sol";

contract ForceDeallocationEnterGateFactory is IForceDeallocationEnterGateFactory {
    address public immutable midnight;
    mapping(address gate => bool) public isForceDeallocationEnterGate;

    constructor(address _midnight) {
        midnight = _midnight;
    }

    function createForceDeallocationEnterGate(
        address creditRoleSetter,
        address debtRoleSetter,
        bool creditOpen,
        bool debtOpen,
        bytes32 preSalt
    ) external returns (address) {
        address gate = address(
            new ForceDeallocationEnterGate{salt: keccak256(abi.encode(preSalt, msg.sender))}(
                midnight, creditRoleSetter, debtRoleSetter, creditOpen, debtOpen
            )
        );
        isForceDeallocationEnterGate[gate] = true;

        emit CreateForceDeallocationEnterGate(
            msg.sender, gate, creditRoleSetter, debtRoleSetter, creditOpen, debtOpen, preSalt
        );
        return gate;
    }
}
