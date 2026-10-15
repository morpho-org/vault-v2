// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Morpho Association
pragma solidity >=0.5.0;

interface IForceDeallocationEnterGateFactory {
    event CreateForceDeallocationEnterGate(
        address indexed caller,
        address indexed gate,
        address creditRoleSetter,
        address debtRoleSetter,
        bool creditOpen,
        bool debtOpen,
        bytes32 preSalt
    );

    function isForceDeallocationEnterGate(address gate) external view returns (bool);
    function createForceDeallocationEnterGate(
        address creditRoleSetter,
        address debtRoleSetter,
        bool creditOpen,
        bool debtOpen,
        bytes32 preSalt
    ) external returns (address);
}
