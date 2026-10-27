// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Morpho Association
pragma solidity 0.8.37;

import {VaultV2CompatibleEnterGate} from "./VaultV2CompatibleEnterGate.sol";
import {IVaultV2CompatibleEnterGateFactory} from "./interfaces/IVaultV2CompatibleEnterGateFactory.sol";

contract VaultV2CompatibleEnterGateFactory is IVaultV2CompatibleEnterGateFactory {
    address public immutable midnight;

    mapping(address account => bool) public isCreated;
    mapping(address subGate => mapping(bytes32 salt => address)) public vaultV2CompatibleEnterGate;

    constructor(address _midnight) {
        midnight = _midnight;
    }

    function createVaultV2CompatibleEnterGate(address subGate, bytes32 salt) external returns (address) {
        address gate = address(new VaultV2CompatibleEnterGate{salt: salt}(subGate, midnight));
        vaultV2CompatibleEnterGate[subGate][salt] = gate;
        isCreated[gate] = true;
        emit CreateVaultV2CompatibleEnterGate(gate, subGate);
        return gate;
    }
}
