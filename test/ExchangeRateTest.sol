// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import "./BaseTest.sol";
import {StdStorage, stdStorage} from "forge-std/StdStorage.sol";

contract ExchangeRateTest is BaseTest {
    using stdStorage for StdStorage;

    uint256 constant MIN_DEPOSIT = 1 ether;
    uint256 constant MAX_DEPOSIT = 1e18 ether;

    function setUp() public override {
        super.setUp();
        deal(address(underlyingToken), address(this), type(uint256).max);
        underlyingToken.approve(address(vault), type(uint256).max);
    }

    function testExchangeRateDepositRedeem(uint256 amount) public {
        amount = bound(amount, MIN_DEPOSIT, MAX_DEPOSIT);
        vault.deposit(amount, address(this));

        assertEq(underlyingToken.balanceOf(address(vault)), amount, "wrong deposit amount");
        assertEq(vault.totalAssets(), amount, "wrong totalAssets");

        underlyingToken.transfer(address(vault), amount);
        stdstore.target(address(vault)).sig(vault.totalAssets.selector).checked_write(2 * amount);

        assertEq(underlyingToken.balanceOf(address(vault)), 2 * amount, "wrong deposit amount");
        assertEq(vault.totalAssets(), 2 * amount, "wrong totalAssets");

        uint256 newAmount = vault.redeem(vault.balanceOf(address(this)), address(this), address(this));

        assertApproxEqRel(newAmount, 2 * amount, 0.01e18);
    }
}
