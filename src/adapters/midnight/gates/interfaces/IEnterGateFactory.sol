// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Morpho Association
pragma solidity >=0.5.0;

interface IEnterGateFactory {
    function isCreated(address account) external view returns (bool);
}
