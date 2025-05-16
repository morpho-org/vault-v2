// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.28;

import "../src/VaultV2.sol";

contract VaultV2Harness is VaultV2 {
    constructor(address owner, address asset) VaultV2(owner, asset) {}

    function enterExternal(uint256 assets, uint256, address) external {
        if (liquidityAdapter != address(0)) {
            try this.allocate(liquidityAdapter, liquidityData, assets) {} catch {}
        }
    }
}
