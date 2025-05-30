// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import "./BaseTest.sol";

contract MainFunctionsTest is BaseTest {
    using MathLib for uint256;

    uint256 internal constant MAX_TEST_ASSETS = 1e36;
    uint256 internal constant MAX_TEST_SHARES = 1e36;
    uint256 internal constant INITIAL_DEPOSIT = 1e18;

    uint256 internal initialSharesDeposit;
    uint256 internal totalAssetsAfterInterest;

    function setUp() public override {
        super.setUp();

        deal(address(underlyingToken), address(this), INITIAL_DEPOSIT, true);
        underlyingToken.approve(address(vault), type(uint256).max);

        initialSharesDeposit = vault.deposit(INITIAL_DEPOSIT, address(this));

        assertEq(underlyingToken.balanceOf(address(vault)), INITIAL_DEPOSIT, "balanceOf(vault)");
        assertEq(underlyingToken.totalSupply(), INITIAL_DEPOSIT, "totalSupply token");

        assertEq(vault.balanceOf(address(this)), initialSharesDeposit, "balanceOf(this)");
        assertEq(vault.totalSupply(), initialSharesDeposit, "totalSupply vault");

        // Accrue some interest to make sure there is a rounding error.
        vm.prank(allocator);
        vic.increaseInterestPerSecond(uint256(2e18) / (365 days));
        skip(10);
        vault.accrueInterest();
        assertNotEq((vault.totalAssets() + 1) % (vault.totalSupply() + 1), 0);

        totalAssetsAfterInterest = vault.totalAssets();
        deal(address(underlyingToken), address(vault), totalAssetsAfterInterest);

        assertEq(underlyingToken.balanceOf(address(vault)), totalAssetsAfterInterest, "balanceOf(vault)");
    }

    function testMint(uint256 shares, address receiver) public {
        vm.assume(receiver != address(0));
        shares = bound(shares, 0, MAX_TEST_SHARES);

        uint256 expectedAssets = shares.mulDivUp(vault.totalAssets() + 1, vault.totalSupply() + 1);
        uint256 previewedAssets = vault.previewMint(shares);
        assertEq(previewedAssets, expectedAssets, "assets != expectedAssets");

        deal(address(underlyingToken), address(this), expectedAssets, true);
        vm.expectEmit();
        emit EventsLib.Deposit(address(this), receiver, expectedAssets, shares);
        uint256 assets = vault.mint(shares, receiver);

        assertEq(assets, expectedAssets, "assets != expectedAssets");

        assertEq(underlyingToken.balanceOf(address(vault)), totalAssetsAfterInterest + assets, "balanceOf(vault)");
        assertEq(underlyingToken.totalSupply(), INITIAL_DEPOSIT + assets, "total supply");

        uint256 expectedShares = receiver == address(this) ? initialSharesDeposit + shares : shares;
        assertEq(vault.balanceOf(receiver), expectedShares, "balanceOf(receiver)");
        assertEq(vault.totalSupply(), initialSharesDeposit + shares, "total supply");
    }

    function testDeposit(uint256 assets, address receiver) public {
        vm.assume(receiver != address(0));
        assets = bound(assets, 0, MAX_TEST_ASSETS);

        uint256 expectedShares = assets.mulDivDown(vault.totalSupply() + 1, vault.totalAssets() + 1);
        uint256 previewedShares = vault.previewDeposit(assets);
        assertEq(previewedShares, expectedShares, "previewedShares != expectedShares");

        deal(address(underlyingToken), address(this), assets, true);
        vm.expectEmit();
        emit EventsLib.Deposit(address(this), receiver, assets, expectedShares);
        uint256 shares = vault.deposit(assets, receiver);

        assertEq(shares, expectedShares, "shares != expectedShares");

        assertEq(underlyingToken.balanceOf(address(vault)), totalAssetsAfterInterest + assets, "balanceOf(vault)");
        assertEq(underlyingToken.totalSupply(), INITIAL_DEPOSIT + assets, "total supply");

        uint256 expectedTotalShares = receiver == address(this) ? initialSharesDeposit + shares : shares;
        assertEq(vault.balanceOf(receiver), expectedTotalShares, "balanceOf(receiver)");
        assertEq(vault.totalSupply(), initialSharesDeposit + shares, "total supply");
    }

    function testRedeem(uint256 shares, address receiver) public {
        vm.assume(receiver != address(0));
        vm.assume(receiver != address(this));
        vm.assume(receiver != address(vault));
        shares = bound(shares, 0, initialSharesDeposit);

        uint256 expectedAssets = shares.mulDivDown(vault.totalAssets() + 1, vault.totalSupply() + 1);
        uint256 previewedAssets = vault.previewRedeem(shares);
        assertEq(previewedAssets, expectedAssets, "previewedAssets != expectedAssets");

        console.log(vault.balanceOf(address(this)));
        vm.expectEmit();
        emit EventsLib.Withdraw(address(this), receiver, address(this), expectedAssets, shares);
        uint256 assets = vault.redeem(shares, receiver, address(this));

        assertEq(assets, expectedAssets, "assets != expectedAssets");

        if (receiver == address(vault)) {
            assertEq(underlyingToken.balanceOf(address(vault)), totalAssetsAfterInterest, "balanceOf(vault)");
            assertEq(underlyingToken.totalSupply(), INITIAL_DEPOSIT, "total supply");
        } else {
            assertEq(underlyingToken.balanceOf(address(vault)), totalAssetsAfterInterest - assets, "balanceOf(vault)");
            assertEq(underlyingToken.balanceOf(receiver), assets, "balanceOf(receiver)");
            assertEq(underlyingToken.totalSupply(), INITIAL_DEPOSIT, "total supply");
        }

        assertEq(vault.balanceOf(address(this)), initialSharesDeposit - shares, "balanceOf(address(this))");
        assertEq(vault.totalSupply(), initialSharesDeposit - shares, "total supply");
    }

    function testWithdraw(uint256 assets, address receiver) public {
        vm.assume(receiver != address(0));
        assets = bound(assets, 0, INITIAL_DEPOSIT);

        uint256 expectedShares = assets.mulDivUp(vault.totalSupply() + 1, vault.totalAssets() + 1);
        uint256 previewedShares = vault.previewWithdraw(assets);
        assertEq(previewedShares, expectedShares, "previewedShares != expectedShares");

        vm.expectEmit();
        emit EventsLib.Withdraw(address(this), receiver, address(this), assets, expectedShares);
        uint256 shares = vault.withdraw(assets, receiver, address(this));

        assertEq(shares, expectedShares, "shares != expectedShares");

        if (receiver == address(vault)) {
            assertEq(underlyingToken.balanceOf(address(vault)), totalAssetsAfterInterest, "balanceOf(vault)");
            assertEq(underlyingToken.totalSupply(), INITIAL_DEPOSIT, "total supply");
        } else {
            assertEq(underlyingToken.balanceOf(address(vault)), totalAssetsAfterInterest - assets, "balanceOf(vault)");
            assertEq(underlyingToken.balanceOf(receiver), assets, "balanceOf(receiver)");
            assertEq(underlyingToken.totalSupply(), INITIAL_DEPOSIT, "total supply");
        }

        assertEq(vault.balanceOf(address(this)), initialSharesDeposit - shares, "balanceOf(address(this))");
        assertEq(vault.totalSupply(), initialSharesDeposit - shares, "total supply");
    }
}
