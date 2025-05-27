// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import "./BlueIntegrationTest.sol";

contract BlueIntegrationDepositTest is BlueIntegrationTest {
    using MorphoBalancesLib for IMorpho;

    function testDepositNoLiquidityAdapter(uint256 assets) public {
        assets = bound(assets, 0, MAX_TEST_ASSETS);

        vault.deposit(assets, address(this));

        assertEq(underlyingToken.balanceOf(address(morpho)), 0, "underlying balance of Morpho");
        assertEq(underlyingToken.balanceOf(address(adapter)), 0, "underlying balance of adapter");
        assertEq(underlyingToken.balanceOf(address(vault)), assets, "underlying balance of vault");
    }

    function testDepositLiquidityAdapterSuccess(uint256 assets) public {
        assets = bound(assets, 0, MAX_TEST_ASSETS);

        vm.startPrank(allocator);
        vault.setLiquidityAdapter(address(adapter));
        vault.setLiquidityData(abi.encode(marketParams1));
        vm.stopPrank();

        vault.deposit(assets, address(this));

        assertEq(morpho.expectedSupplyAssets(marketParams1, address(adapter)), assets, "expected assets of adapter");
        assertEq(underlyingToken.balanceOf(address(morpho)), assets, "underlying balance of Morpho");
        assertEq(underlyingToken.balanceOf(address(adapter)), 0, "underlying balance of adapter");
        assertEq(underlyingToken.balanceOf(address(vault)), 0, "underlying balance of vault");
    }
}
