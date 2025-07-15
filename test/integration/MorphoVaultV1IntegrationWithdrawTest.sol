// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Morpho Association
pragma solidity ^0.8.0;

import "./MorphoVaultV1IntegrationTest.sol";

contract MorphoVaultV1IntegrationWithdrawTest is MorphoVaultV1IntegrationTest {
    using MorphoBalancesLib for IMorpho;

    address internal immutable receiver = makeAddr("receiver");
    address internal immutable borrower = makeAddr("borrower");

    uint256 internal initialInIdle = 0.3e18 - 1;
    uint256 internal initialInMorphoVaultV1 = 0.7e18;
    uint256 internal initialTotal = 1e18 - 1;

    function setUp() public virtual override {
        super.setUp();

        assertEq(initialTotal, initialInIdle + initialInMorphoVaultV1);

        vault.deposit(initialTotal, address(this));

        setSupplyQueueAllMarkets();

        vm.prank(allocator);
        vault.allocate(address(morphoVaultV1Adapter), hex"", initialInMorphoVaultV1);

        assertEq(underlyingToken.balanceOf(address(vault)), initialInIdle);
        assertEq(underlyingToken.balanceOf(address(morpho)), initialInMorphoVaultV1);
    }

    function testWithdrawLessThanIdle(uint256 assets) public {
        assets = bound(assets, 0, initialInIdle);

        vault.withdraw(assets, receiver, address(this));

        assertEq(underlyingToken.balanceOf(receiver), assets);
        assertEq(underlyingToken.balanceOf(address(vault)), initialInIdle - assets);
        assertEq(underlyingToken.balanceOf(address(morpho)), initialInMorphoVaultV1);
        assertEq(underlyingToken.balanceOf(address(morphoVaultV1)), 0);
        assertEq(underlyingToken.balanceOf(address(morphoVaultV1Adapter)), 0);
        assertEq(
            morphoVaultV1.previewRedeem(morphoVaultV1.balanceOf(address(morphoVaultV1Adapter))), initialInMorphoVaultV1
        );
    }

    function testWithdrawMoreThanIdleNoLiquidityAdapter(uint256 assets) public {
        assets = bound(assets, initialInIdle + 1, MAX_TEST_ASSETS);

        vm.expectRevert();
        vault.withdraw(assets, receiver, address(this));
    }

    function testWithdrawThanksToLiquidityAdapter(uint256 assets) public {
        assets = bound(assets, initialInIdle + 1, initialTotal);
        vm.prank(allocator);
        vault.setLiquidityAdapterAndData(address(morphoVaultV1Adapter), hex"");

        vault.withdraw(assets, receiver, address(this));
        assertEq(underlyingToken.balanceOf(receiver), assets);
        assertEq(underlyingToken.balanceOf(address(vault)), 0);
        assertEq(underlyingToken.balanceOf(address(morpho)), initialTotal - assets);
        assertEq(underlyingToken.balanceOf(address(morphoVaultV1)), 0);
        assertEq(underlyingToken.balanceOf(address(morphoVaultV1Adapter)), 0);
        assertEq(
            morphoVaultV1.previewRedeem(morphoVaultV1.balanceOf(address(morphoVaultV1Adapter))), initialTotal - assets
        );
    }

    function testWithdrawTooMuchEvenWithLiquidityAdapter(uint256 assets) public {
        assets = bound(assets, initialTotal + 1, MAX_TEST_ASSETS);
        vm.prank(allocator);
        vault.setLiquidityAdapterAndData(address(morphoVaultV1Adapter), hex"");

        vm.expectRevert();
        vault.withdraw(assets, receiver, address(this));
    }

    function testWithdrawLiquidityAdapterNoLiquidity(uint256 assets) public {
        assets = bound(assets, initialInIdle + 1, initialTotal);
        vm.prank(allocator);
        vault.setLiquidityAdapterAndData(address(morphoVaultV1Adapter), hex"");

        // Remove liquidity by borrowing.
        deal(address(collateralToken), borrower, type(uint256).max);
        vm.startPrank(borrower);
        collateralToken.approve(address(morpho), type(uint256).max);
        morpho.supplyCollateral(allMarketParams[0], 2 * initialInMorphoVaultV1, borrower, hex"");
        morpho.borrow(allMarketParams[0], initialInMorphoVaultV1, 0, borrower, borrower);
        vm.stopPrank();
        assertEq(underlyingToken.balanceOf(address(morpho)), 0);

        vm.expectRevert();
        vault.withdraw(assets, receiver, address(this));
    }
}
