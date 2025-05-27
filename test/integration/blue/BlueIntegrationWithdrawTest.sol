// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import "./BlueIntegrationTest.sol";

contract BlueIntegrationWithdrawTest is BlueIntegrationTest {
    using MorphoBalancesLib for IMorpho;

    address internal immutable receiver = makeAddr("receiver");
    address internal immutable borrower = makeAddr("borrower");

    uint256 internal initialInIdle = 0.3e18;
    uint256 internal initialInBlue = 0.7e18;
    uint256 internal initialTotal = 1e18;

    function setUp() public virtual override {
        super.setUp();

        assertEq(initialTotal, initialInIdle + initialInBlue);

        vault.deposit(initialTotal, address(this));

        vm.prank(allocator);
        vault.allocate(address(adapter), abi.encode(marketParams1), initialInBlue);

        assertEq(underlyingToken.balanceOf(address(vault)), initialInIdle);
        assertEq(underlyingToken.balanceOf(address(adapter)), 0);
        assertEq(underlyingToken.balanceOf(address(morpho)), initialInBlue);
        assertEq(morpho.expectedSupplyAssets(marketParams1, address(adapter)), initialInBlue);
    }

    function testWithdrawLessThanIdle(uint256 assets) public {
        assets = bound(assets, 0, initialInIdle);

        vault.withdraw(assets, receiver, address(this));

        assertEq(underlyingToken.balanceOf(receiver), assets);
        assertEq(underlyingToken.balanceOf(address(vault)), initialInIdle - assets);
        assertEq(underlyingToken.balanceOf(address(morpho)), initialInBlue);
        assertEq(underlyingToken.balanceOf(address(adapter)), 0);
    }

    function testWithdrawMoreThanIdleNoLiquidityAdapter(uint256 assets) public {
        assets = bound(assets, initialInIdle + 1, MAX_TEST_ASSETS);

        vm.expectRevert();
        vault.withdraw(assets, receiver, address(this));
    }

    function testWithdrawThanksToLiquidityAdapter(uint256 assets) public {
        assets = bound(assets, initialInIdle + 1, initialTotal);
        vm.startPrank(allocator);
        vault.setLiquidityAdapter(address(adapter));
        vault.setLiquidityData(abi.encode(marketParams1));
        vm.stopPrank();

        vault.withdraw(assets, receiver, address(this));
        assertEq(underlyingToken.balanceOf(receiver), assets);
        assertEq(underlyingToken.balanceOf(address(vault)), 0);
        assertEq(underlyingToken.balanceOf(address(morpho)), initialTotal - assets);
        assertEq(underlyingToken.balanceOf(address(adapter)), 0);
    }

    function testWithdrawTooMuchEvenWithLiquidityAdapter(uint256 assets) public {
        assets = bound(assets, initialTotal + 1, MAX_TEST_ASSETS);
        vm.startPrank(allocator);
        vault.setLiquidityAdapter(address(adapter));
        vault.setLiquidityData(abi.encode(marketParams1));
        vm.stopPrank();

        vm.expectRevert();
        vault.withdraw(assets, receiver, address(this));
    }

    function testWithdrawLiquidityAdapterNoLiquidity(uint256 assets) public {
        assets = bound(assets, initialInIdle + 1, initialTotal);
        vm.startPrank(allocator);
        vault.setLiquidityAdapter(address(adapter));
        vault.setLiquidityData(abi.encode(marketParams1));
        vm.stopPrank();

        // Remove liquidity by borrowing.
        deal(address(collateralToken), borrower, type(uint256).max);
        vm.startPrank(borrower);
        collateralToken.approve(address(morpho), type(uint256).max);
        morpho.supplyCollateral(marketParams1, 2 * initialInBlue, borrower, hex"");
        morpho.borrow(marketParams1, initialInBlue, 0, borrower, borrower);
        vm.stopPrank();
        assertEq(underlyingToken.balanceOf(address(morpho)), 0);

        vm.expectRevert();
        vault.withdraw(assets, receiver, address(this));
    }
}
