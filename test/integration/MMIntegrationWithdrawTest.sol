// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import "./MMIntegrationTest.sol";

contract MMIntegrationWithdrawTest is MMIntegrationTest {
    using MorphoBalancesLib for IMorpho;

    address internal immutable receiver = makeAddr("receiver");
    address internal immutable borrower = makeAddr("borrower");

    uint256 internal initialInIdle = 0.3e18;
    uint256 internal initialInMM = 0.7e18;
    uint256 internal initialTotal = 1e18;

    function setUp() public virtual override {
        super.setUp();

        assertEq(initialTotal, initialInIdle + initialInMM);

        vault.deposit(initialTotal, address(this));

        setSupplyQueueAllMarkets();

        vm.prank(allocator);
        vault.allocate(address(metaMorphoAdapter), hex"", initialInMM);

        assertEq(underlyingToken.balanceOf(address(vault)), initialInIdle);
        assertEq(underlyingToken.balanceOf(address(morpho)), initialInMM);
    }

    function testWithdrawLessThanIdle(uint256 assets) public {
        assets = bound(assets, 0, initialInIdle);

        vault.withdraw(assets, receiver, address(this));

        assertEq(underlyingToken.balanceOf(receiver), assets);
        assertEq(underlyingToken.balanceOf(address(vault)), initialInIdle - assets);
        assertEq(underlyingToken.balanceOf(address(morpho)), initialInMM);
        assertEq(underlyingToken.balanceOf(address(metaMorpho)), 0);
        assertEq(underlyingToken.balanceOf(address(metaMorphoAdapter)), 0);
        assertEq(metaMorpho.previewRedeem(metaMorpho.balanceOf(address(metaMorphoAdapter))), initialInMM);
    }

    function testWithdrawMoreThanIdleNoLiquidityAdapter(uint256 assets) public {
        assets = bound(assets, initialInIdle + 1, MAX_TEST_ASSETS);

        vm.expectRevert();
        vault.withdraw(assets, receiver, address(this));
    }

    function testWithdrawThanksToLiquidityAdapter(uint256 assets) public {
        assets = bound(assets, initialInIdle + 1, initialTotal);
        vm.prank(allocator);
        vault.setLiquidityAdapter(address(metaMorphoAdapter));

        vault.withdraw(assets, receiver, address(this));
        assertEq(underlyingToken.balanceOf(receiver), assets);
        assertEq(underlyingToken.balanceOf(address(vault)), 0);
        assertEq(underlyingToken.balanceOf(address(morpho)), initialTotal - assets);
        assertEq(underlyingToken.balanceOf(address(metaMorpho)), 0);
        assertEq(underlyingToken.balanceOf(address(metaMorphoAdapter)), 0);
        assertEq(metaMorpho.previewRedeem(metaMorpho.balanceOf(address(metaMorphoAdapter))), initialTotal - assets);
    }

    function testWithdrawTooMuchEvenWithLiquidityAdapter(uint256 assets) public {
        assets = bound(assets, initialTotal + 1, MAX_TEST_ASSETS);
        vm.prank(allocator);
        vault.setLiquidityAdapter(address(metaMorphoAdapter));

        vm.expectRevert();
        vault.withdraw(assets, receiver, address(this));
    }

    function testWithdrawLiquidityAdapterNoLiquidity(uint256 assets) public {
        assets = bound(assets, initialInIdle + 1, initialTotal);
        vm.prank(allocator);
        vault.setLiquidityAdapter(address(metaMorphoAdapter));

        // Remove liquidity by borrowing.
        deal(address(collateralToken), borrower, type(uint256).max);
        vm.startPrank(borrower);
        collateralToken.approve(address(morpho), type(uint256).max);
        morpho.supplyCollateral(allMarketParams[0], 2 * initialInMM, borrower, hex"");
        morpho.borrow(allMarketParams[0], initialInMM, 0, borrower, borrower);
        vm.stopPrank();
        assertEq(underlyingToken.balanceOf(address(morpho)), 0);

        vm.expectRevert();
        vault.withdraw(assets, receiver, address(this));
    }
}
