// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Morpho Association
pragma solidity ^0.8.0;

import "./BaseTest.sol";

contract MainFunctionsTest is BaseTest {
    using MathLib for uint256;

    uint256 internal constant MAX_TEST_ASSETS = 1e36;
    uint256 internal constant MAX_TEST_SHARES = 1e36;
    uint256 internal constant INITIAL_DEPOSIT = 1e18 - 123456789;

    uint256 internal initialSharesDeposit;
    uint256 internal totalAssetsAfterInterest;

    function setUp() public override {
        super.setUp();

        vm.prank(allocator);
        vault.setMaxRate(MAX_MAX_RATE);

        deal(address(underlyingToken), address(this), INITIAL_DEPOSIT, true);
        underlyingToken.approve(address(vault), type(uint256).max);

        initialSharesDeposit = vault.deposit(INITIAL_DEPOSIT, address(this));

        assertEq(underlyingToken.balanceOf(address(vault)), INITIAL_DEPOSIT, "balanceOf(vault)");
        assertEq(underlyingToken.totalSupply(), INITIAL_DEPOSIT, "totalSupply token");

        assertEq(vault.balanceOf(address(this)), initialSharesDeposit, "balanceOf(this)");
        assertEq(vault.totalSupply(), initialSharesDeposit, "totalSupply vault");

        // Make sure there is a rounding error.
        skip(1); // needed since the max rate.
        deal(address(underlyingToken), address(this), 123456789);
        underlyingToken.transfer(address(vault), 123456789);
        assertNotEq((vault.totalAssets() + 1) % (vault.totalSupply() + vault.virtualShares()), 0);

        assertEq(underlyingToken.balanceOf(address(vault)), 1e18, "balanceOf(vault)");
        totalAssetsAfterInterest = vault.totalAssets();
    }

    function testPostConstruction(address _owner, address asset) public {
        vm.assume(asset != address(vm));
        vm.assume(asset != CONSOLE);
        vm.mockCall(asset, IERC20.decimals.selector, abi.encode(uint8(18)));

        vm.expectEmit();
        emit EventsLib.Constructor(_owner, asset);
        VaultV2 _vault = new VaultV2(_owner, asset);
        assertEq(_vault.owner(), _owner);
        assertEq(_vault.asset(), asset);
        assertEq(_vault.lastUpdate(), block.timestamp);
    }

    function testMint(uint256 shares, address receiver) public {
        vm.assume(receiver != address(0));
        shares = bound(shares, 0, MAX_TEST_SHARES);

        uint256 expectedAssets = shares.mulDivUp(vault.totalAssets() + 1, vault.totalSupply() + vault.virtualShares());
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

        uint256 expectedShares = assets.mulDivDown(vault.totalSupply() + vault.virtualShares(), vault.totalAssets() + 1);
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

    function testRedeem(uint256 shares, uint256 sharesApproved, address receiver, address spender, bool approveMax)
        public
    {
        vm.assume(receiver != address(0));
        vm.assume(receiver != spender);
        vm.assume(receiver != address(vault));
        shares = bound(shares, 0, initialSharesDeposit);
        sharesApproved = bound(sharesApproved, shares, shares * 2);

        uint256 expectedAssets = shares.mulDivDown(vault.totalAssets() + 1, vault.totalSupply() + vault.virtualShares());
        uint256 previewedAssets = vault.previewRedeem(shares);
        assertEq(previewedAssets, expectedAssets, "previewedAssets != expectedAssets");

        vault.approve(spender, approveMax ? type(uint256).max : sharesApproved);

        vm.expectEmit();
        emit EventsLib.Withdraw(spender, receiver, address(this), expectedAssets, shares);
        vm.prank(spender);
        uint256 assets = vault.redeem(shares, receiver, address(this));

        assertEq(assets, expectedAssets, "assets != expectedAssets");

        if (approveMax) {
            assertEq(vault.allowance(address(this), spender), type(uint256).max, " approve max");
        } else {
            if (address(this) == spender) {
                assertEq(vault.allowance(address(this), spender), sharesApproved, "self approved");
            } else {
                assertEq(vault.allowance(address(this), spender), sharesApproved - shares, "approved-redeemed");
            }
        }

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

    function testWithdraw(uint256 assets, uint256 sharesApproved, address receiver, address spender, bool approveMax)
        public
    {
        vm.assume(receiver != address(0));
        assets = bound(assets, 0, INITIAL_DEPOSIT);

        uint256 expectedShares = assets.mulDivUp(vault.totalSupply() + vault.virtualShares(), vault.totalAssets() + 1);
        uint256 previewedShares = vault.previewWithdraw(assets);
        assertEq(previewedShares, expectedShares, "previewedShares != expectedShares");

        sharesApproved = bound(sharesApproved, previewedShares, previewedShares * 2);
        vault.approve(spender, approveMax ? type(uint256).max : sharesApproved);

        vm.expectEmit();
        emit EventsLib.Withdraw(spender, receiver, address(this), assets, expectedShares);

        vm.prank(spender);
        uint256 shares = vault.withdraw(assets, receiver, address(this));

        assertEq(shares, expectedShares, "shares != expectedShares");

        if (approveMax) {
            assertEq(vault.allowance(address(this), spender), type(uint256).max, " approve max");
        } else {
            if (address(this) == spender) {
                assertEq(vault.allowance(address(this), spender), sharesApproved, "self approved");
            } else {
                assertEq(vault.allowance(address(this), spender), sharesApproved - shares, "approved-redeemed");
            }
        }

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
