// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Morpho Association
pragma solidity 0.8.37;

import {VaultV2CompatibleEnterGate} from "./VaultV2CompatibleEnterGate.sol";
import {IVaultV2CompatibleEnterGateFactory} from "./interfaces/IVaultV2CompatibleEnterGateFactory.sol";

contract VaultV2CompatibleEnterGateFactory is IVaultV2CompatibleEnterGateFactory {
    mapping(address account => bool) public isCreated;
    mapping(address subGate => mapping(bytes32 salt => address)) public vaultV2CompatibleEnterGate;

    /// @dev The salt is derived from msg.sender to prevent front-running issues. Bundles (shared msg.sender) must derive preSalt from the initiator too.
    function createVaultV2CompatibleEnterGate(address subGate, bytes32 preSalt) external returns (address) {
        bytes32 salt = keccak256(abi.encode(preSalt, msg.sender));
        address gate = address(new VaultV2CompatibleEnterGate{salt: salt}(subGate));
        vaultV2CompatibleEnterGate[subGate][salt] = gate;
        isCreated[gate] = true;
        emit CreateVaultV2CompatibleEnterGate(msg.sender, gate, subGate, preSalt);
        return gate;
    }
}
