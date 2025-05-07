// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import "./BaseTest.sol";
import {StdStorage, stdStorage} from "forge-std/StdStorage.sol";

contract ExchangeRateTest is BaseTest {
    using stdStorage for StdStorage;

    uint256 constant INITIAL_DEPOSIT = 1e24;
    uint256 constant MIN_TEST_ASSETS = 1e18;
    uint256 constant MAX_TEST_ASSETS = 1e36;
    uint256 constant PRECISION = 1; // precision is 1e(-16)%

    function setUp() public override {
        super.setUp();
        deal(address(underlyingToken), address(this), type(uint256).max);
        underlyingToken.approve(address(vault), type(uint256).max);

        vault.deposit(INITIAL_DEPOSIT, address(this));

        assertEq(underlyingToken.balanceOf(address(vault)), INITIAL_DEPOSIT, "wrong balance before");
        assertEq(vault.totalAssets(), INITIAL_DEPOSIT, "wrong totalAssets before");

        underlyingToken.transfer(address(vault), INITIAL_DEPOSIT);
        stdstore.target(address(vault)).sig(vault.totalAssets.selector).checked_write(2 * INITIAL_DEPOSIT);

        assertEq(underlyingToken.balanceOf(address(vault)), 2 * INITIAL_DEPOSIT, "wrong balance after");
        assertEq(vault.totalAssets(), 2 * INITIAL_DEPOSIT, "wrong totalAssets after");
    }

    function testExchangeRateRedeem(uint256 redeemShares) public {
        redeemShares = bound(redeemShares, MIN_TEST_ASSETS, vault.balanceOf(address(this)));
        uint256 redeemedAssets = vault.redeem(redeemShares, address(this), address(this));

        assertApproxEqRel(redeemedAssets, 2 * redeemShares, PRECISION);
    }

    function testExchangeRateWithdraw(uint256 withdrawAssets) public {
        withdrawAssets = bound(withdrawAssets, MIN_TEST_ASSETS, INITIAL_DEPOSIT);
        uint256 withdrawShares = vault.withdraw(withdrawAssets, address(this), address(this));

        assertApproxEqRel(withdrawAssets, 2 * withdrawShares, PRECISION);
    }

    function testExchangeRateMint(uint256 mintShares) public {
        mintShares = bound(mintShares, MIN_TEST_ASSETS, MAX_TEST_ASSETS);
        uint256 mintAssets = vault.mint(mintShares, address(this));

        assertApproxEqRel(mintAssets, 2 * mintShares, PRECISION);
    }

    function testExchangeRateDeposit(uint256 depositAssets) public {
        depositAssets = bound(depositAssets, MIN_TEST_ASSETS, MAX_TEST_ASSETS);
        uint256 depositShares = vault.deposit(depositAssets, address(this));

        assertApproxEqRel(depositAssets, 2 * depositShares, PRECISION);
    }
}
