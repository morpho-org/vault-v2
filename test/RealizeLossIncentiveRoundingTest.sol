// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Morpho Association
pragma solidity ^0.8.0;

import {BaseTest} from "./BaseTest.sol";
import {ConstantsLib} from "../src/libraries/ConstantsLib.sol";

using ConstantsLib for *;

contract RealizeLossIncentiveRoundingTest is BaseTest {
    AdapterMock internal adapter;

    function setUp() public override {
        super.setUp();

        adapter = new AdapterMock(address(vault));

        vm.prank(curator);
        vault.submit(abi.encodeCall(IVaultV2.setIsAdapter, (address(adapter), true)));
        vault.setIsAdapter(address(adapter), true);

        deal(address(underlyingToken), address(this), type(uint256).max);
        underlyingToken.approve(address(vault), type(uint256).max);

        increaseAbsoluteCap(expectedIdData[0], type(uint128).max);
        increaseAbsoluteCap(expectedIdData[1], type(uint128).max);
        increaseRelativeCap(expectedIdData[0], WAD);
        increaseRelativeCap(expectedIdData[1], WAD);
    }

    function testRealizeLossIncentiveRoundingSmallLoss() public {
        // Setup: deposit some assets
        uint256 deposit = 1e18;
        vault.deposit(deposit, address(this));
        
        // Create a very small loss that will result in zero incentive due to rounding
        // For a 1% incentive ratio, we need loss * 0.01e18 < 1e18 to get zero incentive
        // This means loss < 1e20 (100 tokens)
        uint256 smallLoss = 1e16; // 0.01 tokens
        
        // Mock the adapter to return this small loss
        adapter.setLoss(smallLoss);
        
        // Call realizeLoss
        (uint256 incentiveShares, uint256 loss) = vault.realizeLoss(address(adapter), hex"");
        
        // Verify the loss was realized
        assertEq(loss, smallLoss, "Loss should match expected loss");
        
        // Verify that incentive shares are zero due to rounding
        assertEq(incentiveShares, 0, "Incentive shares should be zero due to rounding");
    }
    
    function testRealizeLossIncentiveRoundingLargeLoss() public {
        // Setup: deposit some assets
        uint256 deposit = 1e18;
        vault.deposit(deposit, address(this));
        
        // Create a larger loss that will result in non-zero incentive
        uint256 largeLoss = 1e20; // 100 tokens
        
        // Mock the adapter to return this large loss
        adapter.setLoss(largeLoss);
        
        // Call realizeLoss
        (uint256 incentiveShares, uint256 loss) = vault.realizeLoss(address(adapter), hex"");
        
        // Verify the loss was realized
        assertEq(loss, largeLoss, "Loss should match expected loss");
        
        // Verify that incentive shares are non-zero
        assertGt(incentiveShares, 0, "Incentive shares should be non-zero for large loss");
    }
    
    function testRealizeLossIncentiveCalculation() public {
        // Setup: deposit some assets
        uint256 deposit = 1e18;
        vault.deposit(deposit, address(this));
        
        // Calculate the minimum loss needed to get non-zero incentive
        // tentativeIncentive = loss * LOSS_REALIZATION_INCENTIVE_RATIO / WAD
        // For non-zero incentive: loss * 0.01e18 >= 1e18
        // Therefore: loss >= 1e20 (100 tokens)
        uint256 minLossForIncentive = 1e20;
        
        // Test with exactly the minimum loss
        adapter.setLoss(minLossForIncentive);
        (uint256 incentiveShares1, ) = vault.realizeLoss(address(adapter), hex"");
        
        // Test with slightly less than minimum loss
        uint256 slightlyLessLoss = minLossForIncentive - 1;
        adapter.setLoss(slightlyLessLoss);
        (uint256 incentiveShares2, ) = vault.realizeLoss(address(adapter), hex"");
        
        // The first should have non-zero incentive, the second should have zero
        assertGt(incentiveShares1, 0, "Should have incentive for minimum loss");
        assertEq(incentiveShares2, 0, "Should have zero incentive for slightly less loss");
    }
}