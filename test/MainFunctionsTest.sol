// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import "./BaseTest.sol";

contract MainFunctionsTest is BaseTest {
    using MathLib for uint256;

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

    function testMintRoundsAssetsUp() public {
        uint256 shares = 100;
        address depositor = makeAddr("depositor");

        vm.prank(allocator);
        vic.setInterestPerSecond(uint256(2e18) / (365 days));
        skip(10);

        vault.accrueInterest();
        uint256 assetsDown = shares.mulDivDown(vault.totalAssets() + 1, vault.totalSupply() + 1);

        deal(address(underlyingToken), depositor, shares * 2);
        vm.startPrank(depositor);
        underlyingToken.approve(address(vault), type(uint256).max);
        uint256 assets = vault.mint(shares, depositor);
        vm.stopPrank();

        assertEq(assets, 101);
        assertNotEq(assets, assetsDown, "vacuous test");
    }

    function testDeposit(uint256 assets, address receiver) public {
        vm.assume(receiver != address(0));
        assets = bound(assets, 0, MAX_TEST_ASSETS);

        uint256 shares = vault.previewDeposit(assets);
        deal(address(underlyingToken), address(this), assets, true);
        vm.expectEmit();
        emit EventsLib.Deposit(address(this), receiver, assets, shares);
        uint256 minted = vault.deposit(assets, receiver);

        assertEq(shares, minted, "shares != minted");

        assertEq(underlyingToken.balanceOf(address(vault)), INITIAL_DEPOSIT + assets, "balanceOf(vault)");
        assertEq(underlyingToken.totalSupply(), INITIAL_DEPOSIT + assets, "total supply");

        uint256 expectedShares = receiver == address(this) ? initialSharesDeposit + shares : shares;
        assertEq(vault.balanceOf(receiver), expectedShares, "balanceOf(receiver)");
        assertEq(vault.totalSupply(), initialSharesDeposit + shares, "total supply");
    }

    function testDepositRoundsSharesDown() public {
        uint256 assets = 100;
        address depositor = makeAddr("depositor");

        vm.prank(allocator);
        vic.setInterestPerSecond(uint256(2e18) / (365 days));
        skip(10);

        vault.accrueInterest();
        uint256 sharesUp = assets.mulDivUp(vault.totalSupply() + 1, vault.totalAssets() + 1);

        deal(address(underlyingToken), depositor, assets);
        vm.startPrank(depositor);
        underlyingToken.approve(address(vault), type(uint256).max);
        uint256 shares = vault.deposit(assets, depositor);
        vm.stopPrank();

        assertEq(shares, 99);
        assertNotEq(shares, sharesUp, "vacuous test");
    }

    function testRedeem(uint256 shares, address receiver) public {
        vm.assume(receiver != address(0));
        vm.assume(receiver != address(this));
        vm.assume(receiver != address(vault));
        shares = bound(shares, 0, initialSharesDeposit);

        uint256 assets = vault.previewRedeem(shares);
        vm.expectEmit();
        emit EventsLib.Withdraw(address(this), receiver, address(this), assets, shares);
        uint256 withdrawn = vault.redeem(shares, receiver, address(this));

        assertEq(assets, withdrawn, "assets != withdrawn");

        if (receiver == address(vault)) {
            assertEq(underlyingToken.balanceOf(address(vault)), INITIAL_DEPOSIT, "balanceOf(vault)");
            assertEq(underlyingToken.totalSupply(), INITIAL_DEPOSIT, "total supply");
        } else {
            assertEq(underlyingToken.balanceOf(address(vault)), INITIAL_DEPOSIT - assets, "balanceOf(vault)");
            assertEq(underlyingToken.balanceOf(receiver), assets, "balanceOf(receiver)");
            assertEq(underlyingToken.totalSupply(), INITIAL_DEPOSIT, "total supply");
        }

        assertEq(vault.balanceOf(address(this)), initialSharesDeposit - shares, "balanceOf(address(this))");
        assertEq(vault.totalSupply(), initialSharesDeposit - shares, "total supply");
    }

    function testRedeemRoundsAssetsDown() public {
        uint256 shares = 100;
        address depositor = makeAddr("depositor");

        deal(address(underlyingToken), depositor, shares * 2);
        vm.startPrank(depositor);
        underlyingToken.approve(address(vault), type(uint256).max);
        vault.mint(shares, depositor);
        vm.stopPrank();

        vm.prank(allocator);
        vic.setInterestPerSecond(uint256(3e18) / (365 days));
        skip(10);

        vault.accrueInterest();
        uint256 assetsUp = shares.mulDivUp(vault.totalAssets() + 1, vault.totalSupply() + 1);

        vm.prank(depositor);
        uint256 assets = vault.redeem(shares, depositor, depositor);

        assertEq(assets, 100);
        assertNotEq(assets, assetsUp, "vacuous test");
    }

    function testWithdraw(uint256 assets, address receiver) public {
        vm.assume(receiver != address(0));
        assets = bound(assets, 0, INITIAL_DEPOSIT);

        uint256 shares = vault.previewWithdraw(assets);
        vm.expectEmit();
        emit EventsLib.Withdraw(address(this), receiver, address(this), assets, shares);
        uint256 redeemed = vault.withdraw(assets, receiver, address(this));

        assertEq(redeemed, shares, "redeemed != shares");

        if (receiver == address(vault)) {
            assertEq(underlyingToken.balanceOf(address(vault)), INITIAL_DEPOSIT, "balanceOf(vault)");
            assertEq(underlyingToken.totalSupply(), INITIAL_DEPOSIT, "total supply");
        } else {
            assertEq(underlyingToken.balanceOf(address(vault)), INITIAL_DEPOSIT - assets, "balanceOf(vault)");
            assertEq(underlyingToken.balanceOf(receiver), assets, "balanceOf(receiver)");
            assertEq(underlyingToken.totalSupply(), INITIAL_DEPOSIT, "total supply");
        }

        assertEq(vault.balanceOf(address(this)), initialSharesDeposit - shares, "balanceOf(address(this))");
        assertEq(vault.totalSupply(), initialSharesDeposit - shares, "total supply");
    }

    function testWithdrawRoundsSharesUp() public {
        uint256 assets = 100;
        address depositor = makeAddr("depositor");

        deal(address(underlyingToken), depositor, assets);
        vm.startPrank(depositor);
        underlyingToken.approve(address(vault), type(uint256).max);
        vault.deposit(assets, depositor);
        vm.stopPrank();

        vm.prank(allocator);
        vic.setInterestPerSecond(uint256(3e18) / (365 days));
        skip(10);

        vault.accrueInterest();
        uint256 sharesDown = assets.mulDivDown(vault.totalSupply() + 1, vault.totalAssets() + 1);

        vm.prank(depositor);
        uint256 shares = vault.withdraw(assets, depositor, depositor);

        assertEq(shares, 100);
        assertNotEq(shares, sharesDown, "vacuous test");
    }
}
