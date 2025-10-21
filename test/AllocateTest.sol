// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Morpho Association
pragma solidity ^0.8.0;

import "./BaseTest.sol";
import {AdapterMock} from "./mocks/AdapterMock.sol";

contract AllocateTest is BaseTest {
    using MathLib for uint256;

    address adapter;
    bytes32[] public ids;

    uint256 maxTestAssets;

    function setUp() public override {
        super.setUp();

        adapter = address(new AdapterMock(address(vault)));

        deal(address(underlyingToken), address(this), type(uint256).max);
        underlyingToken.approve(address(vault), type(uint256).max);

        vm.prank(curator);
        vault.submit(abi.encodeCall(IVaultV2.addAdapter, (adapter)));
        vault.addAdapter(adapter);

        ids = new bytes32[](2);
        ids[0] = keccak256("id-0");
        ids[1] = keccak256("id-1");

        maxTestAssets = 10 ** min(18 + underlyingToken.decimals(), 36);
    }

    function testAllocateZeroAbsoluteCap() public {
        vm.prank(allocator);
        vm.expectRevert(ErrorsLib.ZeroAbsoluteCap.selector);
        vault.allocate(adapter, hex"", 0);
    }

    function testAllocate(bytes memory data, uint256 assets, uint256 allocateAssets, address rdm, uint256 absoluteCap)
        public
    {
        vm.assume(rdm != address(allocator));
        assets = bound(assets, 2, type(uint128).max);
        allocateAssets = bound(allocateAssets, 0, assets);
        absoluteCap = bound(absoluteCap, assets, type(uint128).max);

        // Setup.
        vault.deposit(assets, address(this));
        assertEq(underlyingToken.balanceOf(address(vault)), assets, "Initial vault balance incorrect");
        assertEq(underlyingToken.balanceOf(adapter), 0, "Initial adapter balance incorrect");
        assertEq(vault.allocation(keccak256("id-0")), 0, "Initial allocation incorrect");
        assertEq(vault.allocation(keccak256("id-1")), 0, "Initial allocation incorrect");

        // Can't allocate if not adapter.
        vm.prank(allocator);
        vm.expectRevert(ErrorsLib.NotAdapter.selector);
        vault.allocate(address(this), data, assets);

        // Absolute cap check.
        increaseAbsoluteCap("id-0", assets - 1);
        increaseAbsoluteCap("id-1", assets - 1);
        vm.expectRevert(ErrorsLib.AbsoluteCapExceeded.selector);
        vm.prank(allocator);
        vault.allocate(adapter, data, assets);

        // Access control.
        vm.prank(rdm);
        vm.expectRevert(ErrorsLib.Unauthorized.selector);
        vault.allocate(adapter, data, assets);
        vm.prank(allocator);
        vault.allocate(adapter, hex"", 0);

        // Relative cap check fails on 0 cap.
        increaseAbsoluteCap("id-0", assets);
        increaseAbsoluteCap("id-1", assets);
        vm.expectRevert(ErrorsLib.RelativeCapExceeded.selector);
        vm.prank(allocator);
        vault.allocate(adapter, data, assets);

        // Relative cap check fails on non-WAD cap.
        increaseRelativeCap("id-0", WAD - 1);
        increaseRelativeCap("id-1", WAD - 1);
        vm.expectRevert(ErrorsLib.RelativeCapExceeded.selector);
        vm.prank(allocator);
        vault.allocate(adapter, data, assets);

        uint256 snapshot = vm.snapshotState();

        // Relative cap check passes on non-WAD cap.
        vm.prank(allocator);
        vault.allocate(adapter, data, assets.mulDivDown(WAD - 1, WAD));

        vm.revertToState(snapshot);

        // Normal path.
        increaseRelativeCap("id-0", WAD);
        increaseRelativeCap("id-1", WAD);
        vm.prank(allocator);
        vm.expectEmit();
        emit EventsLib.Allocate(allocator, adapter, allocateAssets, ids, int256(allocateAssets));
        vault.allocate(adapter, data, allocateAssets);
        assertEq(
            underlyingToken.balanceOf(address(vault)),
            assets - allocateAssets,
            "Vault balance incorrect after allocation"
        );
        assertEq(underlyingToken.balanceOf(adapter), allocateAssets, "Adapter balance incorrect after allocation");
        assertEq(vault.allocation(keccak256("id-0")), allocateAssets, "Allocation incorrect after allocation");
        assertEq(vault.allocation(keccak256("id-1")), allocateAssets, "Allocation incorrect after allocation");
        assertEq(AdapterMock(adapter).recordedAllocateData(), data, "Data incorrect after allocation");
        assertEq(AdapterMock(adapter).recordedAllocateAssets(), allocateAssets, "Assets incorrect after allocation");
        assertEq(
            AdapterMock(adapter).recordedSelector(), IVaultV2.allocate.selector, "Selector incorrect after allocation"
        );
        assertEq(AdapterMock(adapter).recordedSender(), allocator, "Sender incorrect after allocation");
    }

    /// forge-config: default.isolate = true
    function testRelativeCapManipulationProtection(uint256 allocation) public {
        allocation = bound(allocation, 1, type(uint128).max / 2 / vault.virtualShares());
        deal(address(underlyingToken), allocator, type(uint256).max);
        vm.prank(allocator);
        underlyingToken.approve(address(vault), type(uint256).max);

        vault.deposit(allocation, address(this));

        increaseAbsoluteCap("id-0", allocation);
        increaseAbsoluteCap("id-1", allocation);
        increaseRelativeCap("id-0", WAD / 2);
        increaseRelativeCap("id-1", WAD / 2);

        // Fails if the deposit and allocation are done in the same transaction.
        bytes[] memory data = new bytes[](3);
        data[0] = abi.encodeCall(vault.deposit, (allocation, allocator));
        data[1] = abi.encodeCall(vault.allocate, (adapter, hex"", allocation));
        data[2] = abi.encodeCall(vault.withdraw, (allocation, allocator, allocator));

        vm.prank(allocator);
        vm.expectRevert(ErrorsLib.RelativeCapExceeded.selector);
        vault.multicall(data);

        // Passes if they are done in separate transactions.
        vm.startPrank(allocator);
        vault.deposit(allocation, allocator);
        vault.allocate(adapter, hex"", allocation);
        vault.withdraw(allocation, allocator, allocator);
    }

    function testAllocateRelativeCapCheckRoundsDown(bytes memory data) public {
        uint256 assets = 100;

        // Setup.
        vault.deposit(assets, address(this));

        increaseAbsoluteCap("id-0", assets);
        increaseAbsoluteCap("id-1", assets);
        increaseRelativeCap("id-0", WAD - 1);
        increaseRelativeCap("id-1", WAD - 1);
        vm.prank(allocator);
        vm.expectRevert(ErrorsLib.RelativeCapExceeded.selector);
        vault.allocate(adapter, data, 100);
    }

    function testDeallocateZeroAllocation() public {
        vm.prank(allocator);
        vm.expectRevert(ErrorsLib.ZeroAllocation.selector);
        vault.deallocate(adapter, hex"", 0);
    }

    function testDeallocate(bytes memory data, uint256 assetsIn, uint256 assetsOut, address rdm, uint256 absoluteCap)
        public
    {
        vm.assume(rdm != address(allocator));
        vm.assume(rdm != address(sentinel));
        assetsIn = bound(assetsIn, 1, maxTestAssets);
        assetsOut = bound(assetsOut, 1, assetsIn);
        absoluteCap = bound(absoluteCap, assetsIn, type(uint128).max);

        // Setup.
        deal(address(underlyingToken), address(vault), assetsIn);
        increaseAbsoluteCap("id-0", assetsIn);
        increaseAbsoluteCap("id-1", assetsIn);
        increaseRelativeCap("id-0", WAD);
        increaseRelativeCap("id-1", WAD);
        vm.prank(allocator);
        vault.allocate(adapter, data, assetsIn);

        // Access control.
        vm.prank(rdm);
        vm.expectRevert(ErrorsLib.Unauthorized.selector);
        vault.deallocate(adapter, hex"", 0);
        vm.prank(allocator);
        vault.deallocate(adapter, hex"", 0);
        vm.prank(sentinel);
        vault.deallocate(adapter, hex"", 0);

        // Can't deallocate if not adapter.
        vm.prank(allocator);
        vm.expectRevert(ErrorsLib.NotAdapter.selector);
        vault.deallocate(address(this), data, assetsOut);

        // Normal path.
        vm.prank(allocator);
        vm.expectEmit();
        emit EventsLib.Deallocate(allocator, adapter, assetsOut, ids, -int256(assetsOut));
        vault.deallocate(adapter, data, assetsOut);
        assertEq(underlyingToken.balanceOf(address(vault)), assetsOut, "Vault balance incorrect after deallocation");
        assertEq(
            underlyingToken.balanceOf(adapter), assetsIn - assetsOut, "Adapter balance incorrect after deallocation"
        );
        assertEq(vault.allocation(keccak256("id-0")), assetsIn - assetsOut, "Allocation incorrect after deallocation");
        assertEq(vault.allocation(keccak256("id-1")), assetsIn - assetsOut, "Allocation incorrect after deallocation");
        assertEq(AdapterMock(adapter).recordedDeallocateData(), data, "Data incorrect after deallocation");
        assertEq(AdapterMock(adapter).recordedDeallocateAssets(), assetsOut, "Assets incorrect after deallocation");
        assertEq(
            AdapterMock(adapter).recordedSelector(),
            IVaultV2.deallocate.selector,
            "Selector incorrect after deallocation"
        );
        assertEq(AdapterMock(adapter).recordedSender(), allocator, "Sender incorrect after deallocation");
    }

    function testAllocateWithInterest(
        uint256 deposit,
        uint256 allocation1,
        uint256 allocation2,
        uint256 interest,
        uint256 cap
    ) public {
        deposit = bound(deposit, 1, maxTestAssets);
        allocation1 = bound(allocation1, 0, deposit);
        allocation2 = bound(allocation2, 0, deposit - allocation1);
        interest = bound(interest, 1, maxTestAssets);
        cap = bound(cap, allocation1, type(uint128).max);
        cap = bound(cap, 1, type(uint128).max); // to avoid zero cap.

        // Setup.
        increaseAbsoluteCap("id-0", cap);
        increaseAbsoluteCap("id-1", cap);
        increaseRelativeCap("id-0", WAD);
        increaseRelativeCap("id-1", WAD);
        vault.deposit(deposit, address(this));
        vm.prank(allocator);
        vault.allocate(adapter, hex"", allocation1);
        AdapterMock(adapter).setInterest(interest);

        // Test.
        vm.prank(allocator);
        if (cap >= allocation1 + allocation2 + interest) {
            vm.expectEmit();
            emit EventsLib.Allocate(allocator, adapter, allocation2, ids, int256(allocation2) + int256(interest));
            vault.allocate(adapter, hex"", allocation2);
            assertEq(
                vault.allocation(keccak256("id-0")),
                allocation1 + allocation2 + interest,
                "Allocation incorrect after allocation"
            );
            assertEq(
                vault.allocation(keccak256("id-1")),
                allocation1 + allocation2 + interest,
                "Allocation incorrect after allocation"
            );
        } else {
            vm.expectRevert(ErrorsLib.AbsoluteCapExceeded.selector);
            vault.allocate(adapter, hex"", allocation2);
        }
    }

    function testDeallocateWithInterest(
        uint256 deposit,
        uint256 allocation,
        uint256 deallocation,
        uint256 interest,
        uint256 cap
    ) public {
        deposit = bound(deposit, 1, type(uint128).max);
        allocation = bound(allocation, 1, deposit); // starts at 1 to avoid zero allocation.
        deallocation = bound(deallocation, 0, allocation);
        interest = bound(interest, 1, type(uint128).max);
        cap = bound(cap, allocation, type(uint128).max);
        cap = bound(cap, 1, type(uint128).max); // to avoid zero cap.

        // Setup.
        increaseAbsoluteCap("id-0", cap);
        increaseAbsoluteCap("id-1", cap);
        increaseRelativeCap("id-0", WAD);
        increaseRelativeCap("id-1", WAD);
        vault.deposit(deposit, address(this));
        vm.prank(allocator);
        vault.allocate(adapter, hex"", allocation);
        AdapterMock(adapter).setInterest(interest);

        // Test.
        vm.prank(allocator);
        vault.deallocate(adapter, hex"", deallocation);
        assertEq(
            vault.allocation(keccak256("id-0")),
            allocation - deallocation + interest,
            "Allocation incorrect after deallocation"
        );
        assertEq(
            vault.allocation(keccak256("id-1")),
            allocation - deallocation + interest,
            "Allocation incorrect after deallocation"
        );
    }

    function testAllocateTooMuchNegativeChange(uint256 deposit, uint256 loss) public {
        deposit = bound(deposit, 1, maxTestAssets - 1);
        loss = bound(loss, deposit + 1, maxTestAssets);

        increaseAbsoluteCap("id-0", deposit);
        increaseAbsoluteCap("id-1", deposit);
        increaseRelativeCap("id-0", WAD);
        increaseRelativeCap("id-1", WAD);

        vault.deposit(deposit, address(this));
        vault.accrueInterest(); // to prevent accrueInterest in the allocate (which would revert with AdapterMock).
        AdapterMock(adapter).setLoss(loss);

        vm.prank(allocator);
        vm.expectRevert(ErrorsLib.CastOverflow.selector);
        vault.allocate(adapter, hex"", deposit);
    }

    function testDeallocateTooMuchNegativeChange(uint256 deposit, uint256 loss) public {
        deposit = bound(deposit, 1, maxTestAssets - 1);
        loss = bound(loss, deposit + 1, maxTestAssets);

        increaseAbsoluteCap("id-0", deposit);
        increaseAbsoluteCap("id-1", deposit);
        increaseRelativeCap("id-0", WAD);
        increaseRelativeCap("id-1", WAD);

        vault.deposit(deposit, address(this));
        vm.prank(allocator);
        vault.allocate(adapter, hex"", deposit);
        AdapterMock(adapter).setLoss(loss);

        vm.prank(allocator);
        vm.expectRevert(ErrorsLib.CastOverflow.selector);
        vault.deallocate(adapter, hex"", deposit);
    }
}
