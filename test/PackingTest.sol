// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Morpho Association
pragma solidity ^0.8.0;

import {VaultV2} from "../src/VaultV2.sol";

import {ERC20Mock} from "./mocks/ERC20Mock.sol";

import {Test, console} from "../lib/forge-std/src/Test.sol";

// The packed slot containing both _totalAssets and lastUpdate.
bytes32 constant TOTAL_ASSETS_AND_LAST_UPDATE_PACKED_SLOT = bytes32(uint256(15));

contract PackingTest is VaultV2, Test {
    constructor() VaultV2(address(0), address(new ERC20Mock(18))) {}

    function testTotalAssetsAndLastUpdateSlot() public pure {
        bytes32 _totalAssetsSlot;
        bytes32 lastUpdateSlot;
        assembly {
            _totalAssetsSlot := _totalAssets.slot
            lastUpdateSlot := lastUpdate.slot
        }
        assertEq(_totalAssetsSlot, TOTAL_ASSETS_AND_LAST_UPDATE_PACKED_SLOT, "wrong _totalAssets slot");
        assertEq(lastUpdateSlot, TOTAL_ASSETS_AND_LAST_UPDATE_PACKED_SLOT, "wrong lastUpdate slot");
    }
}
