// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Morpho Association
pragma solidity >=0.5.0;

import {IEnterGateFactory} from "./IEnterGateFactory.sol";

interface IVaultV2CompatibleEnterGateFactory is IEnterGateFactory {
    /* EVENTS */

    event CreateVaultV2CompatibleEnterGate(
        address indexed caller,
        address indexed vaultV2CompatibleEnterGate,
        address indexed subGate,
        bool admitEnabled,
        bytes32 preSalt
    );

    /* FUNCTIONS */

    function createVaultV2CompatibleEnterGate(address subGate, bool admitEnabled, bytes32 preSalt)
        external
        returns (address);
}
