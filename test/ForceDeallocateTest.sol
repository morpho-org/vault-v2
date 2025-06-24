// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Morpho Association
pragma solidity ^0.8.0;

import "./BaseTest.sol";

contract ForceDeallocateTest is BaseTest {
    using MathLib for uint256;

    uint256 constant MAX_TEST_ASSETS = 1e36;
    address adapter;

    function setUp() public override {
        super.setUp();

        adapter = address(new AdapterMock(address(vault)));
        vm.prank(curator);
        vault.submit(abi.encodeCall(IVaultV2.setIsAdapter, (adapter, true)));
        vault.setIsAdapter(adapter, true);

        increaseAbsoluteCap("id-0", type(uint128).max);
        increaseAbsoluteCap("id-1", type(uint128).max);
        increaseRelativeCap("id-0", WAD);
        increaseRelativeCap("id-1", WAD);

        deal(address(underlyingToken), address(this), type(uint256).max);
        underlyingToken.approve(address(vault), type(uint256).max);
    }

    function testForceDeallocate(uint256 supplied, uint256 deallocated, uint256 forceDeallocatePenalty) public {
        supplied = bound(supplied, 1, MAX_TEST_ASSETS); // starts at 1 to avoid zero allocation.
        deallocated = bound(deallocated, 0, supplied);
        forceDeallocatePenalty = bound(forceDeallocatePenalty, 0, MAX_FORCE_DEALLOCATE_PENALTY);

        uint256 shares = vault.deposit(supplied, address(this));
        assertEq(underlyingToken.balanceOf(address(vault)), supplied);

        vm.prank(allocator);
        vault.allocate(address(adapter), hex"", supplied);
        assertEq(underlyingToken.balanceOf(adapter), supplied);

        vm.prank(curator);
        vault.submit(abi.encodeCall(IVaultV2.setForceDeallocatePenalty, (adapter, forceDeallocatePenalty)));
        vault.setForceDeallocatePenalty(adapter, forceDeallocatePenalty);

        uint256 penaltyAssets = deallocated.mulDivUp(forceDeallocatePenalty, WAD);
        uint256 expectedShares = shares - vault.previewWithdraw(penaltyAssets);
        vm.expectEmit();
        emit EventsLib.ForceDeallocate(address(this), adapter, hex"", deallocated, address(this), penaltyAssets);
        uint256 withdrawnShares = vault.forceDeallocate(adapter, hex"", deallocated, address(this));
        assertEq(shares - expectedShares, withdrawnShares);
        assertEq(underlyingToken.balanceOf(adapter), supplied - deallocated);
        assertEq(underlyingToken.balanceOf(address(vault)), deallocated);
        assertEq(vault.balanceOf(address(this)), expectedShares);

        vault.withdraw(min(deallocated, vault.previewRedeem(expectedShares)), address(this), address(this));
    }
}
