// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import "./BaseTest.sol";

contract MainFunctionsTest is BaseTest {
    uint256 internal constant MAX_TEST_ASSETS = 1e36;
    uint256 internal constant MAX_TEST_SHARES = 1e36;
    uint256 internal constant INITIAL_DEPOSIT = 1e18;

    uint256 internal initialSharesDeposit;

    function setUp() public override {
        super.setUp();

        deal(address(underlyingToken), address(this), INITIAL_DEPOSIT, true);
        underlyingToken.approve(address(vault), type(uint256).max);

        initialSharesDeposit = vault.deposit(INITIAL_DEPOSIT, address(this));

        assertEq(underlyingToken.balanceOf(address(vault)), INITIAL_DEPOSIT, "balanceOf(vault)");
        assertEq(underlyingToken.totalSupply(), INITIAL_DEPOSIT, "totalSupply token");

        assertEq(vault.balanceOf(address(this)), initialSharesDeposit, "balanceOf(this)");
        assertEq(vault.totalSupply(), initialSharesDeposit, "totalSupply vault");
    }

    function testMint(uint256 shares, address receiver) public {
        vm.assume(receiver != address(0));
        shares = bound(shares, 0, MAX_TEST_SHARES);

        uint256 assets = vault.previewMint(shares);
        deal(address(underlyingToken), address(this), assets, true);
        vm.expectEmit();
        emit EventsLib.Deposit(address(this), receiver, assets, shares);
        uint256 deposited = vault.mint(shares, receiver);

        assertEq(assets, deposited, "assets != deposited");

        assertEq(underlyingToken.balanceOf(address(vault)), INITIAL_DEPOSIT + assets, "balanceOf(vault)");
        assertEq(underlyingToken.totalSupply(), INITIAL_DEPOSIT + assets, "total supply");

        uint256 expectedShares = receiver == address(this) ? initialSharesDeposit + shares : shares;
        assertEq(vault.balanceOf(receiver), expectedShares, "balanceOf(receiver)");
        assertEq(vault.totalSupply(), initialSharesDeposit + shares, "total supply");
    }

    function testDeposit(uint256 assets, address receiver) public {
        vm.assume(receiver != address(0));
        assets = bound(assets, 0, MAX_TEST_ASSETS);

        uint256 shares = vault.previewDeposit(assets);
        deal(address(underlyingToken), address(this), assets, true);
        vm.expectEmit();
        emit EventsLib.Deposit(address(this), receiver, assets, shares);
        uint256 deposited = vault.deposit(assets, receiver);

        assertEq(shares, deposited, "shares != deposited");

        assertEq(underlyingToken.balanceOf(address(vault)), INITIAL_DEPOSIT + assets, "balanceOf(vault)");
        assertEq(underlyingToken.totalSupply(), INITIAL_DEPOSIT + assets, "total supply");

        uint256 expectedShares = receiver == address(this) ? initialSharesDeposit + shares : shares;
        assertEq(vault.balanceOf(receiver), expectedShares, "balanceOf(receiver)");
        assertEq(vault.totalSupply(), initialSharesDeposit + shares, "total supply");
    }

    function testRedeem(uint256 shares, address receiver) public {
        vm.assume(receiver != address(0));
        shares = bound(shares, 0, initialSharesDeposit);

        uint256 assets = vault.previewRedeem(shares);
        vm.expectEmit();
        emit EventsLib.Withdraw(address(this), receiver, address(this), assets, shares);
        uint256 redeemed = vault.redeem(shares, receiver, address(this));

        assertEq(assets, redeemed, "assets != redeemed");

        assertEq(underlyingToken.balanceOf(address(vault)), INITIAL_DEPOSIT - assets, "balanceOf(vault)");
        assertEq(underlyingToken.balanceOf(receiver), assets, "balanceOf(receiver)");
        assertEq(underlyingToken.totalSupply(), INITIAL_DEPOSIT, "total supply");

        assertEq(vault.balanceOf(address(this)), initialSharesDeposit - shares, "balanceOf(address(this))");
        assertEq(vault.totalSupply(), initialSharesDeposit - shares, "total supply");
    }

    function testWithdraw(uint256 assets, address receiver) public {
        vm.assume(receiver != address(0));
        vm.assume(receiver != address(this));
        assets = bound(assets, 0, INITIAL_DEPOSIT);

        uint256 shares = vault.previewWithdraw(assets);
        vm.expectEmit();
        emit EventsLib.Withdraw(address(this), receiver, address(this), assets, shares);
        uint256 withdrawn = vault.withdraw(assets, receiver, address(this));

        assertEq(withdrawn, shares, "withdrawn != shares");

        assertEq(underlyingToken.balanceOf(address(vault)), INITIAL_DEPOSIT - assets, "balanceOf(vault)");
        assertEq(underlyingToken.balanceOf(receiver), assets, "balanceOf(receiver)");
        assertEq(underlyingToken.totalSupply(), INITIAL_DEPOSIT, "total supply");

        assertEq(vault.balanceOf(address(this)), initialSharesDeposit - shares, "balanceOf(address(this))");
        assertEq(vault.totalSupply(), initialSharesDeposit - shares, "total supply");
    }
}
