// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Morpho Association
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";
import {BaseTest} from "../BaseTest.sol";
import {FeeWrapperDeployer} from "../../src/periphery/FeeWrapperDeployer.sol";
import {IVaultV2} from "../../src/interfaces/IVaultV2.sol";
import {IMorphoVaultV1Adapter} from "../../src/adapters/interfaces/IMorphoVaultV1Adapter.sol";
import {IMorphoVaultV1AdapterFactory} from "../../src/adapters/interfaces/IMorphoVaultV1AdapterFactory.sol";
import {MorphoVaultV1AdapterFactory} from "../../src/adapters/MorphoVaultV1AdapterFactory.sol";
import {MAX_MAX_RATE, MAX_PERFORMANCE_FEE, MAX_MANAGEMENT_FEE, WAD} from "../../src/libraries/ConstantsLib.sol";

contract FeeWrapperDeployerTest is BaseTest {
    FeeWrapperDeployer public feeWrapperDeployer;
    IVaultV2 public childVault;
    IMorphoVaultV1AdapterFactory public morphoVaultV1AdapterFactory;

    function setUp() public override {
        super.setUp();

        childVault = IVaultV2(vaultFactory.createVaultV2(owner, address(underlyingToken), bytes32(uint256(1))));

        // Set up child vault with maxRate so it can accrue interest.
        vm.startPrank(owner);
        childVault.setCurator(owner);
        childVault.submit(abi.encodeCall(IVaultV2.setIsAllocator, (owner, true)));
        childVault.setIsAllocator(owner, true);
        childVault.setMaxRate(MAX_MAX_RATE);
        vm.stopPrank();

        feeWrapperDeployer = new FeeWrapperDeployer();
        morphoVaultV1AdapterFactory = IMorphoVaultV1AdapterFactory(address(new MorphoVaultV1AdapterFactory()));
    }

    function testCreateFeeWrapper() public {
        address feeWrapper = feeWrapperDeployer.createFeeWrapper(
            address(vaultFactory), address(morphoVaultV1AdapterFactory), owner, bytes32(uint256(2)), address(childVault)
        );

        // Get the created adapter from the factory.
        address adapter = morphoVaultV1AdapterFactory.morphoVaultV1Adapter(feeWrapper, address(childVault));

        // assert the mandatory config.
        assertTrue(IVaultV2(feeWrapper).abdicated(IVaultV2.addAdapter.selector));
        assertTrue(IVaultV2(feeWrapper).abdicated(IVaultV2.removeAdapter.selector));
        assertTrue(IVaultV2(feeWrapper).abdicated(IVaultV2.setAdapterRegistry.selector));

        // assert rest of the config
        assertTrue(IVaultV2(feeWrapper).owner() == owner);
        assertTrue(IVaultV2(feeWrapper).curator() == owner);
        assertTrue(IVaultV2(feeWrapper).receiveSharesGate() == address(0));
        assertTrue(IVaultV2(feeWrapper).sendSharesGate() == address(0));
        assertTrue(IVaultV2(feeWrapper).receiveAssetsGate() == address(0));
        assertTrue(IVaultV2(feeWrapper).sendAssetsGate() == address(0));
        assertTrue(IVaultV2(feeWrapper).adapterRegistry() == address(0));
        assertTrue(IVaultV2(feeWrapper).isSentinel(owner) == true);
        assertTrue(IVaultV2(feeWrapper).isAllocator(owner) == true);
        assertTrue(IVaultV2(feeWrapper).firstTotalAssets() == 0);
        assertTrue(IVaultV2(feeWrapper)._totalAssets() == 0);
        assertTrue(IVaultV2(feeWrapper).lastUpdate() == block.timestamp);
        assertTrue(IVaultV2(feeWrapper).maxRate() == MAX_MAX_RATE);
        assertTrue(IVaultV2(feeWrapper).adaptersLength() == 1);
        assertTrue(IVaultV2(feeWrapper).adapters(0) == adapter);
        assertTrue(IVaultV2(feeWrapper).allocation(keccak256(abi.encode("this", adapter))) == 0);
        assertTrue(IVaultV2(feeWrapper).absoluteCap(keccak256(abi.encode("this", adapter))) == type(uint128).max);
        assertTrue(IVaultV2(feeWrapper).relativeCap(keccak256(abi.encode("this", adapter))) == 1e18);
        assertTrue(IVaultV2(feeWrapper).liquidityAdapter() == adapter);
        assertTrue(IVaultV2(feeWrapper).liquidityData().length == 0);
        assertTrue(IVaultV2(feeWrapper).forceDeallocatePenalty(adapter) == 0);
        assertTrue(IVaultV2(feeWrapper).timelock(IVaultV2.addAdapter.selector) == 0);
        assertTrue(IVaultV2(feeWrapper).timelock(IVaultV2.removeAdapter.selector) == 0);
        assertTrue(IVaultV2(feeWrapper).timelock(IVaultV2.setAdapterRegistry.selector) == 0);
        assertTrue(IVaultV2(feeWrapper).timelock(IVaultV2.setLiquidityAdapterAndData.selector) == 0);
        assertTrue(IVaultV2(feeWrapper).timelock(IVaultV2.setMaxRate.selector) == 0);
        assertTrue(IVaultV2(feeWrapper).timelock(IVaultV2.setForceDeallocatePenalty.selector) == 0);
        assertTrue(IVaultV2(feeWrapper).timelock(IVaultV2.allocate.selector) == 0);
        assertTrue(IVaultV2(feeWrapper).timelock(IVaultV2.deallocate.selector) == 0);
    }

    function testDeposit() public {
        address feeWrapper = feeWrapperDeployer.createFeeWrapper(
            address(vaultFactory), address(morphoVaultV1AdapterFactory), owner, bytes32(uint256(2)), address(childVault)
        );
        address adapter = morphoVaultV1AdapterFactory.morphoVaultV1Adapter(feeWrapper, address(childVault));
        address depositor = makeAddr("depositor");
        uint256 depositAmount = 1000e18;
        deal(address(underlyingToken), depositor, depositAmount);
        vm.prank(depositor);
        underlyingToken.approve(feeWrapper, depositAmount);

        vm.prank(depositor);
        uint256 shares = IVaultV2(feeWrapper).deposit(depositAmount, depositor);

        assertGt(shares, 0, "should receive shares");
        assertEq(IVaultV2(feeWrapper).balanceOf(depositor), shares, "depositor should have shares");
        assertEq(IVaultV2(feeWrapper).totalAssets(), depositAmount, "total assets should match deposit");
        assertEq(underlyingToken.balanceOf(feeWrapper), 0, "fee wrapper should have no idle assets");
        assertEq(childVault.totalAssets(), depositAmount, "assets should be in child vault");
        bytes32 adapterId = keccak256(abi.encode("this", adapter));
        assertEq(IVaultV2(feeWrapper).allocation(adapterId), depositAmount, "allocation should be tracked");
    }

    function testDepositAndWithdraw() public {
        address feeWrapper = feeWrapperDeployer.createFeeWrapper(
            address(vaultFactory), address(morphoVaultV1AdapterFactory), owner, bytes32(uint256(2)), address(childVault)
        );
        address depositor = makeAddr("depositor");
        uint256 depositAmount = 1000e18;
        deal(address(underlyingToken), depositor, depositAmount);
        vm.prank(depositor);
        underlyingToken.approve(feeWrapper, depositAmount);
        vm.prank(depositor);
        uint256 shares = IVaultV2(feeWrapper).deposit(depositAmount, depositor);

        vm.prank(depositor);
        IVaultV2(feeWrapper).redeem(shares, depositor, depositor);

        assertEq(IVaultV2(feeWrapper).balanceOf(depositor), 0, "depositor should have no shares");
        assertEq(underlyingToken.balanceOf(depositor), depositAmount, "depositor should have assets back");
        assertEq(childVault.totalAssets(), 0, "child vault should be empty");
    }

    /// forge-config: default.isolate = true
    function testPerformanceFee() public {
        address feeWrapper = feeWrapperDeployer.createFeeWrapper(
            address(vaultFactory), address(morphoVaultV1AdapterFactory), owner, bytes32(uint256(2)), address(childVault)
        );
        address feeRecipient = makeAddr("feeRecipient");
        uint256 performanceFee = 0.1e18; // 10%

        vm.startPrank(owner);
        IVaultV2(feeWrapper).submit(abi.encodeCall(IVaultV2.setPerformanceFeeRecipient, (feeRecipient)));
        IVaultV2(feeWrapper).setPerformanceFeeRecipient(feeRecipient);
        IVaultV2(feeWrapper).submit(abi.encodeCall(IVaultV2.setPerformanceFee, (performanceFee)));
        IVaultV2(feeWrapper).setPerformanceFee(performanceFee);
        vm.stopPrank();

        // Deposit into fee wrapper.
        address depositor = makeAddr("depositor");
        uint256 depositAmount = 1000e18;
        deal(address(underlyingToken), depositor, depositAmount);
        vm.prank(depositor);
        underlyingToken.approve(feeWrapper, depositAmount);
        vm.prank(depositor);
        IVaultV2(feeWrapper).deposit(depositAmount, depositor);

        // Skip 1 day and donate yield that's within maxRate limits.
        // With MAX_MAX_RATE (200% APR), max 1-day yield = 1000e18 * 1 day * (200e16 / 365 days) / 1e18
        uint256 elapsed = 1 days;
        vm.warp(block.timestamp + elapsed);
        uint256 yieldAmount = 5e18; // Small yield well within maxRate limits
        deal(address(underlyingToken), address(childVault), childVault.totalAssets() + yieldAmount);

        // Accrue interest on fee wrapper.
        IVaultV2(feeWrapper).accrueInterest();

        // Performance fee should be 10% of the yield.
        uint256 expectedFeeAssets = yieldAmount * performanceFee / WAD; // 5e18 * 0.1 = 0.5e18
        uint256 feeRecipientShares = IVaultV2(feeWrapper).balanceOf(feeRecipient);
        uint256 feeRecipientAssets = IVaultV2(feeWrapper).previewRedeem(feeRecipientShares);

        // Allow some rounding error due to share price calculations.
        assertApproxEqAbs(feeRecipientAssets, expectedFeeAssets, 0.01e18, "performance fee should be ~10% of yield");
    }

    /// forge-config: default.isolate = true
    function testManagementFeeAccrual() public {
        address feeWrapper = feeWrapperDeployer.createFeeWrapper(
            address(vaultFactory), address(morphoVaultV1AdapterFactory), owner, bytes32(uint256(2)), address(childVault)
        );
        address feeRecipient = makeAddr("feeRecipient");
        uint256 managementFee = MAX_MANAGEMENT_FEE; // 5% annual

        vm.startPrank(owner);
        IVaultV2(feeWrapper).submit(abi.encodeCall(IVaultV2.setManagementFeeRecipient, (feeRecipient)));
        IVaultV2(feeWrapper).setManagementFeeRecipient(feeRecipient);
        IVaultV2(feeWrapper).submit(abi.encodeCall(IVaultV2.setManagementFee, (managementFee)));
        IVaultV2(feeWrapper).setManagementFee(managementFee);
        vm.stopPrank();

        // Deposit into fee wrapper.
        address depositor = makeAddr("depositor");
        uint256 depositAmount = 1000e18;
        deal(address(underlyingToken), depositor, depositAmount);
        vm.prank(depositor);
        underlyingToken.approve(feeWrapper, depositAmount);
        vm.prank(depositor);
        IVaultV2(feeWrapper).deposit(depositAmount, depositor);

        // Warp 1 year.
        vm.warp(block.timestamp + 365 days);

        // Accrue interest on fee wrapper.
        IVaultV2(feeWrapper).accrueInterest();

        // Fee recipient should have received management fee shares.
        uint256 feeRecipientShares = IVaultV2(feeWrapper).balanceOf(feeRecipient);
        assertGt(feeRecipientShares, 0, "fee recipient should have shares");

        // Management fee should be approximately 5% of assets over 1 year = 50e18.
        uint256 expectedFee = depositAmount * managementFee * 365 days / WAD;
        uint256 feeRecipientAssets = IVaultV2(feeWrapper).previewRedeem(feeRecipientShares);
        assertApproxEqAbs(feeRecipientAssets, expectedFee, 1e18, "fee should be ~5% annual");
    }
}
