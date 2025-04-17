// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.28;

import {BaseTest} from "./BaseTest.sol";
import {stdError} from "forge-std/StdError.sol";
import "../src/libraries/EventsLib.sol";
import {ErrorsLib} from "../src/libraries/ErrorsLib.sol";

contract ERC20Test is BaseTest {
    uint256 constant MAX_DEPOSIT = 1e18 ether;

    function setUp() public override {
        super.setUp();

        deal(address(underlyingToken), address(this), type(uint256).max);
        underlyingToken.approve(address(vault), type(uint256).max);
    }

    function testMint(uint256 amount) public {
        vm.assume(amount <= MAX_DEPOSIT);

        vm.expectEmit();
        emit EventsLib.Transfer(address(0), address(this), amount);

        vault.mint(amount, address(this));
        assertEq(vault.totalSupply(), amount, "total supply");
        assertEq(vault.balanceOf(address(this)), amount, "balance");
    }

    function testMintZeroAddress(uint256 amount) public {
        vm.expectRevert(ErrorsLib.ZeroAddress.selector);
        vault.mint(amount, address(0));
    }

    function testBurn(uint256 amount, uint256 amountRedeemed) public {
        vm.assume(amount <= MAX_DEPOSIT);
        amountRedeemed = bound(amountRedeemed, 0, amount);

        vault.mint(amount, address(this));
        vm.expectEmit();
        emit EventsLib.Transfer(address(this), address(0), amountRedeemed);

        vault.redeem(amountRedeemed, address(this), address(this));

        assertEq(vault.totalSupply(), amount - amountRedeemed, "total supply");
        assertEq(vault.balanceOf(address(this)), amount - amountRedeemed, "balance");
    }

    function testBurnZeroAddress() public {
        vm.expectRevert(ErrorsLib.ZeroAddress.selector);
        vault.redeem(0, address(this), address(0));
    }

    function testApprove(address spender, uint256 amount) public {
        vm.assume(amount <= MAX_DEPOSIT);
        vm.expectEmit();
        emit EventsLib.Approval(address(this), address(spender), amount);

        assertTrue(vault.approve(spender, amount));
        assertEq(vault.allowance(address(this), spender), amount);
    }

    function testTransfer(address to, uint256 amount, uint256 amountTransferred) public {
        vm.assume(amount <= MAX_DEPOSIT);
        vm.assume(to != address(0));
        amountTransferred = bound(amountTransferred, 0, amount);

        vault.mint(amount, address(this));

        vm.expectEmit();
        emit EventsLib.Transfer(address(this), address(to), amountTransferred);

        assertTrue(vault.transfer(to, amountTransferred));

        assertEq(vault.totalSupply(), amount, "total supply");
        if (address(this) == to) {
            assertEq(vault.balanceOf(address(this)), amount, "balance");
        } else {
            assertEq(vault.balanceOf(address(this)), amount - amountTransferred, "balance from");
            assertEq(vault.balanceOf(to), amountTransferred, "balance to");
        }
    }

    function testTransferZeroAddress(uint256 amount) public {
        vault.mint(amount, address(this));
        vm.expectRevert(ErrorsLib.ZeroAddress.selector);
        vault.transfer(address(0), amount);
    }

    function testTransferFrom(
        address from,
        address to,
        uint256 amount,
        uint256 amountTransferred,
        uint256 amountApproved
    ) public {
        vm.assume(amount <= MAX_DEPOSIT);
        amountApproved = bound(amountApproved, 0, amount);
        amountTransferred = bound(amountTransferred, 0, amountApproved);

        vm.assume(from != address(0));
        vm.assume(to != address(0));
        vault.mint(amount, from);

        vm.prank(from);
        vault.approve(address(this), amountApproved);

        vm.expectEmit();
        emit EventsLib.Transfer(from, to, amountTransferred);
        vault.transferFrom(from, to, amountTransferred);

        assertEq(vault.allowance(from, address(this)), amountApproved - amountTransferred, "allowance");
        if (from == to) {
            assertEq(vault.balanceOf(from), amount, "balance");
        } else {
            assertEq(vault.balanceOf(from), amount - amountTransferred, "balance from");
            assertEq(vault.balanceOf(to), amountTransferred, "balance to");
        }
    }

    function testTransferFromSenderZeroAddress(address to) public {
        vm.assume(to != address(0));
        vm.expectRevert(ErrorsLib.ZeroAddress.selector);
        vault.transferFrom(address(0), to, 0);
        vm.stopPrank();
    }

    function testTransferFromReceiverZeroAddress(address from, uint256 amount) public {
        vm.assume(from != address(0));
        vault.mint(amount, from);
        vm.prank(from);
        vault.approve(address(this), type(uint256).max);
        vm.expectRevert(ErrorsLib.ZeroAddress.selector);
        vault.transferFrom(from, address(0), amount);
    }

    function testInfiniteApproveTransferFrom(address from, address to, uint256 amount, uint256 amountTransferred)
        public
    {
        vm.assume(amount <= MAX_DEPOSIT);
        amountTransferred = bound(amountTransferred, 0, amount);

        vm.assume(from != address(0));
        vm.assume(to != address(0));
        vault.mint(amount, from);

        vm.prank(from);
        vault.approve(address(this), type(uint256).max);

        vm.expectEmit();
        emit EventsLib.Transfer(from, to, amountTransferred);

        vault.transferFrom(from, to, amountTransferred);
        assertEq(vault.allowance(from, address(this)), type(uint256).max, "allowance");
        if (from == to) {
            assertEq(vault.balanceOf(from), amount, "balance");
        } else {
            assertEq(vault.balanceOf(from), amount - amountTransferred, "balance from");
            assertEq(vault.balanceOf(to), amountTransferred, "balance to");
        }
    }

    function testMintOverMaxUintReverts() public {
        vault.mint(type(uint256).max, address(this));
        vm.expectRevert(stdError.arithmeticError);
        vault.mint(1, address(this));
    }

    function testTransferInsufficientBalanceReverts(address to, uint256 amount) public {
        amount = bound(amount, 0, type(uint256).max - 1);
        vm.assume(to != address(0));
        vault.mint(amount, address(this));
        vm.expectRevert(stdError.arithmeticError);
        vault.transfer(to, amount + 1);
    }

    function testTransferFromInsufficientAllowanceReverts(address from, address to, uint256 allowance) public {
        vm.assume(from != address(0));
        vm.assume(to != address(0));

        allowance = bound(allowance, 0, type(uint256).max - 1);
        vault.mint(allowance + 1, from);

        vm.prank(from);
        vault.approve(address(this), allowance);

        vm.expectRevert(stdError.arithmeticError);
        vault.transferFrom(from, to, allowance + 1);
    }

    function testTransferFromInsufficientBalanceReverts(address from, address to, uint256 allowance) public {
        vm.assume(from != address(0));
        vm.assume(to != address(0));
        allowance = bound(allowance, 1, type(uint256).max);
        vault.mint(allowance - 1, from);

        vm.prank(from);
        vault.approve(address(this), allowance);

        vm.expectRevert(stdError.arithmeticError);
        vault.transferFrom(from, to, allowance);
    }

    function testBurnInsufficientBalanceReverts(address to, uint256 mintAmount, uint256 burnAmount) public {
        vm.assume(to != address(0));
        mintAmount = bound(mintAmount, 0, type(uint256).max - 1);
        burnAmount = _bound(burnAmount, mintAmount + 1, type(uint256).max);

        vault.mint(mintAmount, to);
        vm.expectRevert(stdError.arithmeticError);
        vault.redeem(burnAmount, to, to);
    }
}
