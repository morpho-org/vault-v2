// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import "./BaseTest.sol";
import {StdStorage, stdStorage} from "forge-std/StdStorage.sol";

contract ExchangeRateTest is BaseTest {
    using stdStorage for StdStorage;

    uint256 constant MIN_DEPOSIT = 1 ether;
    uint256 constant MAX_DEPOSIT = 1e18 ether;
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

    function testExchangeRateRedeem(uint256 assets, uint256 redeemShares) public {
        assets = bound(assets, MIN_DEPOSIT, MAX_DEPOSIT);
        startWithDoubleExchangeRate(assets);

        redeemShares = bound(redeemShares, MIN_DEPOSIT, vault.balanceOf(address(this)));
        uint256 redeemedAssets = vault.redeem(redeemShares, address(this), address(this));

        assertApproxEqRel(redeemedAssets, 2 * redeemShares, PRECISION);
    }

    function testExchangeRateWithdraw(uint256 assets, uint256 withdrawAssets) public {
        assets = bound(assets, MIN_DEPOSIT, MAX_DEPOSIT);
        startWithDoubleExchangeRate(assets);

        withdrawAssets = bound(withdrawAssets, MIN_DEPOSIT, assets);
        uint256 withdrawShares = vault.withdraw(withdrawAssets, address(this), address(this));

        assertApproxEqRel(withdrawAssets, 2 * withdrawShares, PRECISION);
    }

    function testExchangeRateMint(uint256 assets, uint256 mintShares) public {
        assets = bound(assets, MIN_DEPOSIT, MAX_DEPOSIT);
        startWithDoubleExchangeRate(assets);

        mintShares = bound(mintShares, MIN_DEPOSIT, MAX_DEPOSIT);
        uint256 mintAssets = vault.mint(mintShares, address(this));

        assertApproxEqRel(mintAssets, 2 * mintShares, PRECISION);
    }

    function testExchangeRateDeposit(uint256 assets, uint256 depositAssets) public {
        assets = bound(assets, MIN_DEPOSIT, MAX_DEPOSIT);
        startWithDoubleExchangeRate(assets);

        depositAssets = bound(depositAssets, MIN_DEPOSIT, MAX_DEPOSIT);
        uint256 depositShares = vault.deposit(depositAssets, address(this));

        assertApproxEqRel(depositAssets, 2 * depositShares, PRECISION);
    }
}
