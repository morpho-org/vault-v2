// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import "./MMIntegrationTest.sol";

contract MMIntegrationLiquidityAdapter is MMIntegrationTest {
    using MarketParamsLib for MarketParams;
    using MorphoBalancesLib for IMorpho;

    function testDepositNoLiquidityAdapter(uint256 assets) public {
        assets = bound(assets, 0, MAX_TEST_ASSETS);

        vault.deposit(assets, address(this));

        checkAssetsInVault(assets);
        assertEq(morpho.expectedSupplyAssets(idleParams, address(metaMorpho)), 0, "expected assets of metaMorpho");
    }

    function testDepositLiquidityAdapterSuccess(uint256 assets) public {
        assets = bound(assets, 0, MAX_TEST_ASSETS);

        setUpSimpleQueue();
        vm.prank(allocator);
        vault.setLiquidityAdapter(address(metaMorphoAdapter));

        vault.deposit(assets, address(this));

        checkAssetsInMetaMorpho(assets);
        assertEq(morpho.expectedSupplyAssets(idleParams, address(metaMorpho)), assets, "expected assets of metaMorpho");
    }

    function testDepositLiquidityAdapterCanFail(uint256 assets) public {
        assets = bound(assets, 0, MAX_TEST_ASSETS);

        setUpComplexQueue();
        vm.prank(allocator);
        vault.setLiquidityAdapter(address(metaMorphoAdapter));

        vault.deposit(assets, address(this));

        if (assets > MM_NB_MARKETS * CAP) {
            checkAssetsInVault(assets);
        } else {
            checkAssetsInMetaMorpho(assets);
        }
    }

    function checkAssetsInMetaMorpho(uint256 assets) internal view {
        assertEq(underlyingToken.balanceOf(address(morpho)), assets, "underlying balance of Morpho");
        assertEq(underlyingToken.balanceOf(address(metaMorpho)), 0, "underlying balance of metaMorpho");
        assertEq(underlyingToken.balanceOf(address(metaMorphoAdapter)), 0, "underlying balance of adapter");
        assertEq(underlyingToken.balanceOf(address(vault)), 0, "underlying balance of vault");
    }

    function checkAssetsInVault(uint256 assets) public view {
        assertEq(underlyingToken.balanceOf(address(morpho)), 0, "underlying balance of Morpho");
        assertEq(underlyingToken.balanceOf(address(metaMorpho)), 0, "underlying balance of metaMorpho");
        assertEq(underlyingToken.balanceOf(address(metaMorphoAdapter)), 0, "underlying balance of adapter");
        assertEq(underlyingToken.balanceOf(address(vault)), assets, "underlying balance of vault");
    }
}
