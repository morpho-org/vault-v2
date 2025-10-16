// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Morpho Association
pragma solidity ^0.8.0;

import "./MorphoVaultV1IntegrationTest.sol";

contract MorphoVaultV1IntegrationAllocationTest is MorphoVaultV1IntegrationTest {
    using MorphoBalancesLib for IMorpho;

    address internal immutable borrower = makeAddr("borrower");

    uint256 internal initialInIdle = 0.3e18;
    uint256 internal initialInMorphoVaultV1 = 0.7e18;
    uint256 internal initialTotal = 1e18;

    function setUp() public virtual override {
        super.setUp();

        assertEq(initialTotal, initialInIdle + initialInMorphoVaultV1);

        vault.deposit(initialTotal, address(this));

        setSupplyQueueAllMarkets();

        vm.prank(allocator);
        vault.allocate(address(morphoVaultV1Adapter), hex"", initialInMorphoVaultV1);

        assertEq(underlyingToken.balanceOf(address(vault)), initialInIdle);
        assertEq(underlyingToken.balanceOf(address(morpho)), initialInMorphoVaultV1);
    }

    function testDeallocateLessThanAllocated(uint256 assets) public {
        assets = bound(assets, 0, initialInMorphoVaultV1);

        vm.prank(allocator);
        vault.deallocate(address(morphoVaultV1Adapter), hex"", assets);

        assertEq(underlyingToken.balanceOf(address(vault)), initialInIdle + assets);
        assertEq(underlyingToken.balanceOf(address(morpho)), initialInMorphoVaultV1 - assets);
        assertEq(underlyingToken.balanceOf(address(morphoVaultV1)), 0);
        assertEq(underlyingToken.balanceOf(address(morphoVaultV1Adapter)), 0);
        assertEq(
            morphoVaultV1.previewRedeem(morphoVaultV1.balanceOf(address(morphoVaultV1Adapter))),
            initialInMorphoVaultV1 - assets
        );
    }

    function testDeallocateMoreThanAllocated(uint256 assets) public {
        assets = bound(assets, initialInMorphoVaultV1 + 1, maxTestAssets);

        vm.prank(allocator);
        vm.expectRevert();
        vault.deallocate(address(morphoVaultV1Adapter), hex"", assets);
    }

    function testDeallocateNoLiquidity(uint256 assets) public {
        assets = bound(assets, initialInIdle + 1, initialTotal);
        vm.prank(allocator);
        vault.setLiquidityAdapterAndData(address(morphoVaultV1Adapter), hex"");

        // Remove liquidity by borrowing.
        deal(address(collateralToken), borrower, type(uint256).max);
        vm.startPrank(borrower);
        collateralToken.approve(address(morpho), type(uint256).max);
        morpho.supplyCollateral(allMarketParams[0], 2 * initialInMorphoVaultV1, borrower, hex"");
        morpho.borrow(allMarketParams[0], initialInMorphoVaultV1, 0, borrower, borrower);
        vm.stopPrank();
        assertEq(underlyingToken.balanceOf(address(morpho)), 0);

        vm.prank(allocator);
        vm.expectRevert();
        vault.deallocate(address(morphoVaultV1Adapter), hex"", assets);
    }

    function testAllocateLessThanIdle(uint256 assets) public {
        assets = bound(assets, 0, initialInIdle);

        vm.prank(allocator);
        vault.allocate(address(morphoVaultV1Adapter), hex"", assets);

        assertEq(underlyingToken.balanceOf(address(vault)), initialInIdle - assets);
        assertEq(underlyingToken.balanceOf(address(morpho)), initialInMorphoVaultV1 + assets);
        assertEq(underlyingToken.balanceOf(address(morphoVaultV1)), 0);
        assertEq(underlyingToken.balanceOf(address(morphoVaultV1Adapter)), 0);
        assertEq(
            morphoVaultV1.previewRedeem(morphoVaultV1.balanceOf(address(morphoVaultV1Adapter))),
            initialInMorphoVaultV1 + assets
        );
    }

    function testAllocateMoreThanIdle(uint256 assets) public {
        assets = bound(assets, initialInIdle + 1, maxTestAssets);

        vm.prank(allocator);
        vm.expectRevert(ErrorsLib.TransferReverted.selector);
        vault.allocate(address(morphoVaultV1Adapter), hex"", assets);
    }

    function testAllocateMoreThanMorphoVaultV1Cap(uint256 assets) public {
        assets = bound(assets, 1, maxTestAssets);

        // Put all caps to the limit.
        vm.startPrank(mmCurator);
        morphoVaultV1.submitCap(allMarketParams[0], initialInMorphoVaultV1);
        for (uint256 i = 1; i < MORPHO_VAULT_V1_NB_MARKETS; i++) {
            morphoVaultV1.submitCap(allMarketParams[i], 0);
        }
        vm.stopPrank();

        vm.prank(allocator);
        vm.expectRevert();
        vault.allocate(address(morphoVaultV1Adapter), hex"", assets);
    }
}
