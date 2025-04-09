// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.28;

import {BaseTest} from "./BaseTest.sol";

contract ERC20Test is BaseTest {
    uint256 constant MAX_DEPOSIT = 1e18 ether;

    function setUp() public override {
        super.setUp();

        deal(address(underlyingToken), address(this), type(uint256).max);
        underlyingToken.approve(address(vault), type(uint256).max);
    }

    function testMint(uint256 amount) public {
        vm.assume(amount <= MAX_DEPOSIT);
        vault.mint(amount, address(this));
        assertEq(vault.balanceOf(address(this)), amount);
    }

    function testBurn(uint256 amount) public {
        vm.assume(amount <= MAX_DEPOSIT);
        vault.mint(amount, address(this));
        vault.redeem(amount, address(this), address(this));
        assertEq(vault.balanceOf(address(this)), 0);
    }

    function testApprove(address spender, uint256 amount) public {
        vm.assume(amount <= MAX_DEPOSIT);
        vault.approve(spender, amount);
        assertEq(vault.allowance(address(this), spender), amount);
    }

    function testTransfer(address to, uint256 amount) public {
        vm.assume(amount <= MAX_DEPOSIT);
        vault.mint(amount, address(this));
        vault.transfer(to, amount);
        assertEq(vault.balanceOf(to), amount);
    }

    function testTransferFrom(address to, uint256 amount) public {
        vm.assume(amount <= MAX_DEPOSIT);
        vault.mint(amount, address(this));
        assertEq(vault.balanceOf(address(this)), amount);
        vault.approve(to, amount);
        vm.prank(to);
        vault.transferFrom(address(this), to, amount);
        assertEq(vault.balanceOf(to), amount);
    }
}
