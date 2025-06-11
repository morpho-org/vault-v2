// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import "./BaseTest.sol";

contract ViewFunctionsTest is BaseTest {
    uint256 constant INITIAL_DEPOSIT = 1e24;
    uint256 constant MIN_TEST_ASSETS = 1e18;
    uint256 constant MAX_TEST_ASSETS = 1e36;
    uint256 constant PRECISION = 1;

    address immutable receiver = makeAddr("receiver");
    address immutable gate = makeAddr("gate");

    function setUp() public override {
        super.setUp();
        deal(address(underlyingToken), address(this), type(uint256).max);
        underlyingToken.approve(address(vault), type(uint256).max);
    }

    function testMaxDepositNoGate() public view {
        assertEq(VaultV2(address(vault)).maxDeposit(receiver), type(uint256).max);
    }

    function testMaxMintNoGate() public view {
        assertEq(VaultV2(address(vault)).maxMint(receiver), type(uint256).max);
    }

    function testMaxDepositWithGateCanReceive() public {
        vm.prank(curator);
        vault.submit(abi.encodeCall(IVaultV2.setSharesGate, (gate)));
        vault.setSharesGate(gate);

        vm.mockCall(gate, ISharesGate.canReceiveShares.selector, abi.encode(true));
        assertEq(VaultV2(address(vault)).maxDeposit(receiver), type(uint256).max);
    }

    function testMaxMintWithGateCanReceive() public {
        vm.prank(curator);
        vault.submit(abi.encodeCall(IVaultV2.setSharesGate, (address(gate))));
        vault.setSharesGate(address(gate));

        vm.mockCall(gate, ISharesGate.canReceiveShares.selector, abi.encode(true));
        assertEq(VaultV2(address(vault)).maxMint(receiver), type(uint256).max);
    }

    function testMaxDepositWithGateCannotReceive() public {
        vm.prank(curator);
        vault.submit(abi.encodeCall(IVaultV2.setSharesGate, (address(gate))));
        vault.setSharesGate(address(gate));

        vm.mockCall(gate, ISharesGate.canReceiveShares.selector, abi.encode(false));
        assertEq(VaultV2(address(vault)).maxDeposit(receiver), 0);
    }

    function testMaxMintWithGateCannotReceive() public {
        vm.prank(curator);
        vault.submit(abi.encodeCall(IVaultV2.setSharesGate, (address(gate))));
        vault.setSharesGate(address(gate));

        vm.mockCall(gate, ISharesGate.canReceiveShares.selector, abi.encode(false));
        assertEq(VaultV2(address(vault)).maxMint(receiver), 0);
    }

    function testMaxWithdraw() public view {
        assertEq(VaultV2(address(vault)).maxWithdraw(address(this)), 0);
    }

    function testMaxRedeem() public view {
        assertEq(VaultV2(address(vault)).maxRedeem(address(this)), 0);
    }

    function testConvertToAssets(uint256 initialDeposit, uint256 interest, uint256 shares) public {
        initialDeposit = bound(initialDeposit, 0, MAX_TEST_ASSETS);
        interest = bound(interest, 0, MAX_TEST_ASSETS);
        shares = bound(shares, 0, MAX_TEST_ASSETS);

        vault.deposit(initialDeposit, address(this));
        writeTotalAssets(initialDeposit + interest);

        assertEq(
            IVaultV2(address(vault)).convertToAssets(shares),
            shares * (vault.totalAssets() + 1) / (vault.totalSupply() + 1)
        );
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
            IVaultV2(address(vault)).previewDeposit(initialDeposit),
            initialDeposit * (vault.totalSupply() + 1) / (vault.totalAssets() + 1)
        );
    }

    function testPreviewMint(uint256 initialDeposit, uint256 interest, uint256 shares) public {
        initialDeposit = bound(initialDeposit, 0, MAX_TEST_ASSETS);
        interest = bound(interest, 0, MAX_TEST_ASSETS);
        shares = bound(shares, 0, MAX_TEST_ASSETS);

        vault.deposit(initialDeposit, address(this));
        writeTotalAssets(initialDeposit + interest);

        // Precision 1 because rounded up.
        assertApproxEqAbs(
            IVaultV2(address(vault)).previewMint(shares),
            shares * (vault.totalAssets() + 1) / (vault.totalSupply() + 1),
            1
        );
    }

    function testPreviewWithdraw(uint256 initialDeposit, uint256 interest, uint256 assets) public {
        initialDeposit = bound(initialDeposit, 0, MAX_TEST_ASSETS);
        interest = bound(interest, 0, MAX_TEST_ASSETS);
        assets = bound(assets, 0, MAX_TEST_ASSETS);

        vault.deposit(initialDeposit, address(this));
        writeTotalAssets(initialDeposit + interest);

        // Precision 1 because rounded up.
        assertApproxEqAbs(
            IVaultV2(address(vault)).previewWithdraw(assets),
            assets * (vault.totalSupply() + 1) / (vault.totalAssets() + 1),
            1
        );
    }

    function testPreviewRedeem(uint256 initialDeposit, uint256 interest, uint256 shares) public {
        initialDeposit = bound(initialDeposit, 0, MAX_TEST_ASSETS);
        interest = bound(interest, 0, MAX_TEST_ASSETS);
        shares = bound(shares, 0, MAX_TEST_ASSETS);

        vault.deposit(initialDeposit, address(this));
        writeTotalAssets(initialDeposit + interest);

        assertApproxEqAbs(
            IVaultV2(address(vault)).previewRedeem(shares),
            shares * (vault.totalAssets() + 1) / (vault.totalSupply() + 1),
            1
        );
    }
}
