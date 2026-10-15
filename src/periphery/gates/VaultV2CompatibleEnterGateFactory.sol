// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Morpho Association
pragma solidity 0.8.37;

import {Market} from "lib/midnight/src/interfaces/IMidnight.sol";
import {VaultV2CompatibleEnterGate} from "./VaultV2CompatibleEnterGate.sol";
import {IEnterGateFactory} from "lib/midnight/src/interfaces/IEnterGateFactory.sol";

contract VaultV2CompatibleEnterGateFactory is IEnterGateFactory {
    event CreateVaultV2CompatibleEnterGate(
        address indexed vaultV2CompatibleEnterGate, address indexed subGate, bytes32 marketId
    );

    mapping(address account => mapping(bytes32 marketId => bool)) public isGate;

    function createVaultV2CompatibleEnterGate(address subGate, Market memory market) external returns (address) {
        address vaultV2CompatibleEnterGate = address(new VaultV2CompatibleEnterGate(subGate, market));
        bytes32 marketId = VaultV2CompatibleEnterGate(vaultV2CompatibleEnterGate).marketId();
        isGate[vaultV2CompatibleEnterGate][marketId] = true;
        emit CreateVaultV2CompatibleEnterGate(vaultV2CompatibleEnterGate, subGate, marketId);
        return vaultV2CompatibleEnterGate;
    }
}
