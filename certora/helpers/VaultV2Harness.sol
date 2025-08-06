// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Morpho Association
pragma solidity 0.8.28;

import "../../src/VaultV2.sol";

contract VaultV2Harness is VaultV2 {
    constructor(address owner, address asset) VaultV2(owner, asset) {}

    function getAbsoluteCap(bytes memory idData) external view returns (uint256) {
        bytes32 id = keccak256(idData);
        return caps[id].absoluteCap;
    }

    function getRelativeCap(bytes memory idData) external view returns (uint256) {
        bytes32 id = keccak256(idData);
        return caps[id].relativeCap;
    }
}
