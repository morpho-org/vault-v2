// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Morpho Association
pragma solidity >=0.5.0;

import {IEnterGateFactory} from "./IEnterGateFactory.sol";

interface IVaultV2CompatibleEnterGateFactory is IEnterGateFactory {
    /* EVENTS */

    event CreateVaultV2CompatibleEnterGate(address indexed vaultV2CompatibleEnterGate, address indexed subGate);

    /* FUNCTIONS */

    function midnight() external view returns (address);
    function vaultV2CompatibleEnterGate(address subGate, bytes32 salt) external view returns (address);
    function createVaultV2CompatibleEnterGate(address subGate, bytes32 salt) external returns (address);
}
