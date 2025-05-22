// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import "./MMIntegrationTest.sol";

contract MMIntegrationBadDebtTest is MMIntegrationTest {
    using MorphoBalancesLib for IMorpho;

    uint256 internal initialDeposit = 1.3e18;

    function setUp() public virtual override {
        super.setUp();

        vault.deposit(initialDeposit, address(this));

        setUpComplexQueue();

        vm.prank(allocator);
        vault.allocate(address(metaMorphoAdapter), hex"", initialDeposit);

        assertEq(underlyingToken.balanceOf(address(vault)), 0);
        assertEq(underlyingToken.balanceOf(address(morpho)), initialDeposit);
        assertEq(morpho.expectedSupplyAssets(allMarketParams[0], address(metaMorphoAdapter)), 1e18);
        assertEq(morpho.expectedSupplyAssets(allMarketParams[1], address(metaMorphoAdapter)), 0.3e18);
    }

    function testBadDebt() public {
        assertEq(vault.totalAssets(), initialDeposit);
        assertEq(vault.previewRedeem(vault.balanceOf(address(this))), initialDeposit);

        // Create bad debt.
        vm.startPrank(mmCurator);
        metaMorpho.submitCap(allMarketParams[1], 0);
        metaMorpho.submitMarketRemoval(allMarketParams[1]);
        vm.warp(block.timestamp + metaMorpho.timelock());
        uint256[] memory indexes = new uint256[](4);
        indexes[0] = 0;
        indexes[1] = 2;
        indexes[2] = 3;
        indexes[3] = 4;
        metaMorpho.updateWithdrawQueue(indexes);
        vm.stopPrank();

        vm.prank(allocator);
        vault.deallocate(address(metaMorphoAdapter), hex"", 0);

        uint256 expectedAssets = 1e18;
        assertEq(vault.totalAssets(), expectedAssets);
        assertEq(vault.previewRedeem(vault.balanceOf(address(this))), expectedAssets);
    }
}
