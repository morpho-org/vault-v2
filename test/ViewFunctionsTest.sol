// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Morpho Association
pragma solidity ^0.8.0;

import "./BaseTest.sol";

contract ViewFunctionsTest is BaseTest {
    using MathLib for uint256;

    uint256 MAX_TEST_ASSETS;

    address performanceFeeRecipient = makeAddr("performanceFeeRecipient");
    address managementFeeRecipient = makeAddr("managementFeeRecipient");
    address immutable receiver = makeAddr("receiver");
    AdapterMock adapter;

    function setUp() public override {
        super.setUp();

        MAX_TEST_ASSETS = 10 ** min(18 + underlyingToken.decimals(), 36);

        deal(address(underlyingToken), address(this), type(uint256).max);
        underlyingToken.approve(address(vault), type(uint256).max);

        vm.startPrank(curator);
        vault.submit(abi.encodeCall(IVaultV2.setPerformanceFeeRecipient, (performanceFeeRecipient)));
        vault.submit(abi.encodeCall(IVaultV2.setManagementFeeRecipient, (managementFeeRecipient)));
        vm.stopPrank();

        vault.setPerformanceFeeRecipient(performanceFeeRecipient);
        vault.setManagementFeeRecipient(managementFeeRecipient);

        adapter = new AdapterMock(address(vault));

        vm.prank(curator);
        vault.submit(abi.encodeCall(IVaultV2.addAdapter, (address(adapter))));
        vault.addAdapter(address(adapter));

        vm.prank(allocator);
        vault.setMaxRate(MAX_MAX_RATE);

        vm.prank(allocator);
        vault.setLiquidityAdapterAndData(address(adapter), hex"");

        increaseAbsoluteCap("id-0", type(uint128).max);
        increaseAbsoluteCap("id-1", type(uint128).max);
        increaseRelativeCap("id-0", WAD);
        increaseRelativeCap("id-1", WAD);
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

        assertEq(
            vault.convertToAssets(shares),
            shares * (vault.totalAssets() + 1) / (vault.totalSupply() + vault.virtualShares())
        );
    }

    function testConvertToShares(uint256 initialDeposit, uint256 interest, uint256 assets) public {
        initialDeposit = bound(initialDeposit, 0, MAX_TEST_ASSETS);
        interest = bound(interest, 0, MAX_TEST_ASSETS);
        assets = bound(assets, 0, MAX_TEST_ASSETS);

        vault.deposit(initialDeposit, address(this));
        writeTotalAssets(initialDeposit + interest);

        assertEq(
            vault.convertToShares(assets),
            assets * (vault.totalSupply() + vault.virtualShares()) / (vault.totalAssets() + 1)
        );
    }

    struct TestData {
        uint256 initialDeposit;
        uint256 performanceFee;
        uint256 managementFee;
        uint256 interest;
        uint256 assets;
        uint256 elapsed;
    }

    function setupTest(TestData memory data) internal returns (uint256, uint256) {
        data.initialDeposit = bound(data.initialDeposit, 0, MAX_TEST_ASSETS);
        data.performanceFee = bound(data.performanceFee, 0, MAX_PERFORMANCE_FEE);
        data.managementFee = bound(data.managementFee, 0, MAX_MANAGEMENT_FEE);
        data.elapsed = uint64(bound(data.elapsed, 0, 10 * 365 days));
        data.interest = bound(data.interest, 0, (data.initialDeposit * data.elapsed).mulDivDown(MAX_MAX_RATE, WAD));

        vault.deposit(data.initialDeposit, address(this));

        vm.startPrank(curator);
        vault.submit(abi.encodeCall(IVaultV2.setPerformanceFee, (data.performanceFee)));
        vault.submit(abi.encodeCall(IVaultV2.setManagementFee, (data.managementFee)));
        vm.stopPrank();
        vault.setPerformanceFee(data.performanceFee);
        vault.setManagementFee(data.managementFee);

        adapter.setInterest(data.interest);

        skip(data.elapsed);

        (uint256 newTotalAssets, uint256 performanceFeeShares, uint256 managementFeeShares) = vault.accrueInterestView();

        return (newTotalAssets, vault.totalSupply() + performanceFeeShares + managementFeeShares);
    }

    function testPreviewDeposit(TestData memory data, uint256 assets) public {
        (uint256 newTotalAssets, uint256 newTotalSupply) = setupTest(data);

        assets = bound(assets, 0, MAX_TEST_ASSETS);

        assertEq(vault.previewDeposit(assets), assets * (newTotalSupply + vault.virtualShares()) / (newTotalAssets + 1));
    }

    function testPreviewMint(TestData memory data, uint256 shares) public {
        (uint256 newTotalAssets, uint256 newTotalSupply) = setupTest(data);

        shares = bound(shares, 0, MAX_TEST_ASSETS);

        // Precision 1 because rounded up.
        assertApproxEqAbs(
            vault.previewMint(shares), shares * (newTotalAssets + 1) / (newTotalSupply + vault.virtualShares()), 1
        );
    }

    function testPreviewWithdraw(TestData memory data, uint256 assets) public {
        (uint256 newTotalAssets, uint256 newTotalSupply) = setupTest(data);

        assets = bound(assets, 0, MAX_TEST_ASSETS);

        // Precision 1 because rounded up.
        assertApproxEqAbs(
            vault.previewWithdraw(assets), assets * (newTotalSupply + vault.virtualShares()) / (newTotalAssets + 1), 1
        );
    }

    function testPreviewRedeem(TestData memory data, uint256 shares) public {
        (uint256 newTotalAssets, uint256 newTotalSupply) = setupTest(data);

        shares = bound(shares, 0, MAX_TEST_ASSETS);

        assertEq(vault.previewRedeem(shares), shares * (newTotalAssets + 1) / (newTotalSupply + vault.virtualShares()));
    }
}
