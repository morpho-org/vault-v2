// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Morpho Association
pragma solidity 0.8.37;

import {IKRCompatibleEnterGate} from "./IKRCompatibleEnterGate.sol";
import {IIKRCompatibleEnterGateFactory} from "./interfaces/IIKRCompatibleEnterGateFactory.sol";

contract IKRCompatibleEnterGateFactory is IIKRCompatibleEnterGateFactory {
    mapping(address account => bool) public isCreated;

    /// @dev The salt is derived from msg.sender to prevent front-running issues. Bundles (shared msg.sender) must derive preSalt from the initiator too.
    function createIKRCompatibleEnterGate(address subGate, bool admitEnabled, bytes32 preSalt)
        external
        returns (address)
    {
        bytes32 salt = keccak256(abi.encode(preSalt, msg.sender));
        address gate = address(new IKRCompatibleEnterGate{salt: salt}(subGate, admitEnabled));
        isCreated[gate] = true;
        emit CreateIKRCompatibleEnterGate(msg.sender, gate, subGate, admitEnabled, preSalt);
        return gate;
    }
}
