// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Morpho Association
pragma solidity >=0.5.0;

import {IEnterGateFactory} from "./IEnterGateFactory.sol";

interface IIKRCompatibleEnterGateFactory is IEnterGateFactory {
    /* EVENTS */

    event CreateIKRCompatibleEnterGate(
        address indexed caller,
        address indexed ikrCompatibleEnterGate,
        address indexed subGate,
        bool admitEnabled,
        bytes32 preSalt
    );

    /* FUNCTIONS */

    // forge-lint: disable-next-line(mixed-case-function) IKR is an acronym.
    function createIKRCompatibleEnterGate(address subGate, bool admitEnabled, bytes32 preSalt)
        external
        returns (address);
}
