// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import "./BaseTest.sol";
import {StdStorage, stdStorage} from "forge-std/StdStorage.sol";

contract ExchangeRateTest is BaseTest {
    using stdStorage for StdStorage;

    uint256 constant MIN_TEST_AMOUNT = 1 ether;
    uint256 constant MAX_TEST_AMOUNT = 1e36;
    uint256 constant PRECISION = 1; // precision is 1e(-16)%

    function setUp() public override {
        super.setUp();
        deal(address(underlyingToken), address(this), type(uint256).max);
        underlyingToken.approve(address(vault), type(uint256).max);
    }

    function startWithDoubleExchangeRate(uint256 initialDeposit) internal {
        vault.deposit(initialDeposit, address(this));

        assertEq(underlyingToken.balanceOf(address(vault)), initialDeposit, "wrong balance before");
        assertEq(vault.totalAssets(), initialDeposit, "wrong totalAssets before");

        underlyingToken.transfer(address(vault), initialDeposit);
        stdstore.target(address(vault)).sig(vault.totalAssets.selector).checked_write(2 * initialDeposit);

        assertEq(underlyingToken.balanceOf(address(vault)), 2 * initialDeposit, "wrong balance after");
        assertEq(vault.totalAssets(), 2 * initialDeposit, "wrong totalAssets after");
    }

    function testExchangeRateRedeem(uint256 amount, uint256 redeemShares) public {
        amount = bound(amount, MIN_TEST_AMOUNT, MAX_TEST_AMOUNT);
        startWithDoubleExchangeRate(amount);

        redeemShares = bound(redeemShares, MIN_TEST_AMOUNT, vault.balanceOf(address(this)));
        uint256 redeemedAmount = vault.redeem(redeemShares, address(this), address(this));

        assertApproxEqRel(redeemedAmount, 2 * redeemShares, PRECISION);
    }

    function testExchangeRateWithdraw(uint256 amount, uint256 withdrawAmount) public {
        amount = bound(amount, MIN_TEST_AMOUNT, MAX_TEST_AMOUNT);
        startWithDoubleExchangeRate(amount);

        withdrawAmount = bound(withdrawAmount, MIN_TEST_AMOUNT, amount);
        uint256 withdrawShares = vault.withdraw(withdrawAmount, address(this), address(this));

        assertApproxEqRel(withdrawAmount, 2 * withdrawShares, PRECISION);
    }

    function testExchangeRateMint(uint256 amount, uint256 mintShares) public {
        amount = bound(amount, MIN_TEST_AMOUNT, MAX_TEST_AMOUNT);
        startWithDoubleExchangeRate(amount);

        mintShares = bound(mintShares, MIN_TEST_AMOUNT, MAX_TEST_AMOUNT);
        uint256 mintAssets = vault.mint(mintShares, address(this));

        assertApproxEqRel(mintAssets, 2 * mintShares, PRECISION);
    }

    function testExchangeRateDeposit(uint256 amount, uint256 depositAmount) public {
        amount = bound(amount, MIN_TEST_AMOUNT, MAX_TEST_AMOUNT);
        startWithDoubleExchangeRate(amount);

        depositAmount = bound(depositAmount, MIN_TEST_AMOUNT, MAX_TEST_AMOUNT);
        uint256 depositShares = vault.deposit(depositAmount, address(this));

        assertApproxEqRel(depositAmount, 2 * depositShares, PRECISION);
    }
}
