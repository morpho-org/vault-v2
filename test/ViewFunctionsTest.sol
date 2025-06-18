// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Morpho Association
pragma solidity ^0.8.0;

import "./BaseTest.sol";

contract ViewFunctionsTest is BaseTest {
    uint256 constant MAX_TEST_ASSETS = 1e36;

    address immutable receiver = makeAddr("receiver");

    function setUp() public override {
        super.setUp();
        deal(address(underlyingToken), address(this), type(uint256).max);
        underlyingToken.approve(address(vault), type(uint256).max);
    }

    function testMaxDeposit() public view {
        assertEq(vault.maxDeposit(receiver), 0);
    }

    function testMaxMint() public view {
        assertEq(vault.maxMint(receiver), 0);
    }

    function testMaxWithdraw() public view {
        assertEq(vault.maxWithdraw(address(this)), 0);
    }

    function testMaxRedeem() public view {
        assertEq(vault.maxRedeem(address(this)), 0);
    }

    function testConvertToAssets(uint256 initialDeposit, uint256 interest, uint256 shares) public {
        initialDeposit = bound(initialDeposit, 0, MAX_TEST_ASSETS);
        interest = bound(interest, 0, MAX_TEST_ASSETS);
        shares = bound(shares, 0, MAX_TEST_ASSETS);

        vault.deposit(initialDeposit, address(this));
        writeTotalAssets(initialDeposit + interest);

        assertEq(vault.convertToAssets(shares), shares * (vault.totalAssets() + 1) / (vault.totalSupply() + 1));
    }

    function testConvertToShares(uint256 initialDeposit, uint256 interest, uint256 assets) public {
        initialDeposit = bound(initialDeposit, 0, MAX_TEST_ASSETS);
        interest = bound(interest, 0, MAX_TEST_ASSETS);
        assets = bound(assets, 0, MAX_TEST_ASSETS);

        vault.deposit(initialDeposit, address(this));
        writeTotalAssets(initialDeposit + interest);

        assertEq(
            IVaultV2(address(vault)).convertToShares(assets),
            assets * (vault.totalSupply() + 1) / (vault.totalAssets() + 1)
        );
    }

    function testPreviewDeposit(uint256 initialDeposit, uint256 interest, uint256 assets) public {
        initialDeposit = bound(initialDeposit, 0, MAX_TEST_ASSETS);
        interest = bound(interest, 0, MAX_TEST_ASSETS);
        assets = bound(assets, 0, MAX_TEST_ASSETS);

        vault.deposit(initialDeposit, address(this));
        writeTotalAssets(initialDeposit + interest);

        assertEq(
            vault.previewDeposit(initialDeposit), initialDeposit * (vault.totalSupply() + 1) / (vault.totalAssets() + 1)
        );
    }

    function testPreviewMint(uint256 initialDeposit, uint256 interest, uint256 shares) public {
        initialDeposit = bound(initialDeposit, 0, MAX_TEST_ASSETS);
        interest = bound(interest, 0, MAX_TEST_ASSETS);
        shares = bound(shares, 0, MAX_TEST_ASSETS);

        vault.deposit(initialDeposit, address(this));
        writeTotalAssets(initialDeposit + interest);

        // Precision 1 because rounded up.
        assertApproxEqAbs(vault.previewMint(shares), shares * (vault.totalAssets() + 1) / (vault.totalSupply() + 1), 1);
    }

    function testPreviewWithdraw(uint256 initialDeposit, uint256 interest, uint256 assets) public {
        initialDeposit = bound(initialDeposit, 0, MAX_TEST_ASSETS);
        interest = bound(interest, 0, MAX_TEST_ASSETS);
        assets = bound(assets, 0, MAX_TEST_ASSETS);

        vault.deposit(initialDeposit, address(this));
        writeTotalAssets(initialDeposit + interest);

        // Precision 1 because rounded up.
        assertApproxEqAbs(
            vault.previewWithdraw(assets), assets * (vault.totalSupply() + 1) / (vault.totalAssets() + 1), 1
        );
    }

    function testPreviewRedeem(uint256 initialDeposit, uint256 interest, uint256 shares) public {
        initialDeposit = bound(initialDeposit, 0, MAX_TEST_ASSETS);
        interest = bound(interest, 0, MAX_TEST_ASSETS);
        shares = bound(shares, 0, MAX_TEST_ASSETS);

        vault.deposit(initialDeposit, address(this));
        writeTotalAssets(initialDeposit + interest);

        assertApproxEqAbs(
            vault.previewRedeem(shares), shares * (vault.totalAssets() + 1) / (vault.totalSupply() + 1), 1
        );
    }
}
