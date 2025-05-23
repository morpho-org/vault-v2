// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import "./MMIntegrationTest.sol";

contract MMIntegrationBadDebtTest is MMIntegrationTest {
    using MorphoBalancesLib for IMorpho;

    uint256 internal constant initialDeposit = 1.3e18;
    uint256 internal constant initialOnMarket0 = 1e18;
    uint256 internal constant initialOnMarket1 = 0.3e18;

    function setUp() public virtual override {
        super.setUp();

        assertEq(initialDeposit, initialOnMarket0 + initialOnMarket1);

        vault.deposit(initialDeposit, address(this));

        setSupplyQueueAllMarkets();

        vm.prank(allocator);
        vault.allocate(address(metaMorphoAdapter), hex"", initialDeposit);

        assertEq(underlyingToken.balanceOf(address(vault)), 0);
        assertEq(underlyingToken.balanceOf(address(metaMorphoAdapter)), 0);
        assertEq(underlyingToken.balanceOf(address(metaMorpho)), 0);

        assertEq(underlyingToken.balanceOf(address(morpho)), initialDeposit);
        assertEq(morpho.expectedSupplyAssets(allMarketParams[0], address(metaMorpho)), initialOnMarket0);
        assertEq(morpho.expectedSupplyAssets(allMarketParams[1], address(metaMorpho)), initialOnMarket1);
    }

    function testBadDebt() public {
        assertEq(vault.totalAssets(), initialDeposit);
        assertEq(vault.previewRedeem(vault.balanceOf(address(this))), initialDeposit);

        // Create bad debt by removing market1.
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

        assertEq(vault.totalAssets(), initialOnMarket0);
        assertEq(vault.previewRedeem(vault.balanceOf(address(this))), initialOnMarket0);
    }
}
