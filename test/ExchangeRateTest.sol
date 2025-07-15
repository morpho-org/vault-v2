// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Morpho Association
pragma solidity ^0.8.0;

import "./BaseTest.sol";
import {StdStorage, stdStorage} from "../lib/forge-std/src/StdStorage.sol";

contract ExchangeRateTest is BaseTest {
    using stdStorage for StdStorage;

    uint256 constant INITIAL_DEPOSIT = 1e24;
    uint256 MAX_TEST_ASSETS;
    uint256 totalAssets;
    uint256 totalSupply;

    function setUp() public override {
        super.setUp();

        MAX_TEST_ASSETS = 10 ** min(18 + underlyingToken.decimals(), 36);

        deal(address(underlyingToken), address(this), type(uint256).max);
        underlyingToken.approve(address(vault), type(uint256).max);

        vault.deposit(INITIAL_DEPOSIT, address(this));

        assertEq(underlyingToken.balanceOf(address(vault)), INITIAL_DEPOSIT, "wrong balance before");
        assertEq(vault.totalAssets(), INITIAL_DEPOSIT, "wrong totalAssets before");

        underlyingToken.transfer(address(vault), INITIAL_DEPOSIT);
        writeTotalAssets(2 * INITIAL_DEPOSIT);

        totalAssets = vault.totalAssets();
        totalSupply = vault.totalSupply();

        assertEq(underlyingToken.balanceOf(address(vault)), 2 * INITIAL_DEPOSIT, "wrong balance after");
        assertEq(vault.totalAssets(), 2 * INITIAL_DEPOSIT, "wrong totalAssets after");
        assertEq(vault.totalSupply(), INITIAL_DEPOSIT * vault.virtualShares(), "wrong totalSupply");
    }

    function testVirtualShares() public view {
        uint256 underlyingDecimals = underlyingToken.decimals();
        assertEq(vault.virtualShares(), 10 ** (underlyingDecimals <= 18 ? 18 - underlyingDecimals : 0));
    }

    function testDecimals() public view {
        uint256 underlyingDecimals = underlyingToken.decimals();
        assertEq(vault.decimals(), underlyingDecimals <= 18 ? 18 : underlyingDecimals);
    }

    function testExchangeRateRedeem(uint256 shares) public {
        shares = bound(shares, 0, vault.balanceOf(address(this)));
        uint256 assets = vault.redeem(shares, address(this), address(this));

        assertEq(assets, shares * (totalAssets + 1) / (totalSupply + vault.virtualShares()));
    }

    function testExchangeRateWithdraw(uint256 assets) public {
        assets = bound(assets, 0, INITIAL_DEPOSIT);
        uint256 shares = vault.withdraw(assets, address(this), address(this));

        assertApproxEqAbs(shares, assets * (totalSupply + vault.virtualShares()) / (totalAssets + 1), 1);
    }

    function testExchangeRateMint(uint256 shares) public {
        shares = bound(shares, 0, MAX_TEST_ASSETS);
        uint256 assets = vault.mint(shares, address(this));

        assertApproxEqAbs(assets, shares * (totalAssets + 1) / (totalSupply + vault.virtualShares()), 1);
    }

    function testExchangeRateDeposit(uint256 assets) public {
        assets = bound(assets, 0, MAX_TEST_ASSETS);
        uint256 shares = vault.deposit(assets, address(this));

        assertEq(shares, assets * (totalSupply + vault.virtualShares()) / (totalAssets + 1));
    }
}
