// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import "./BaseTest.sol";
import {AdapterMock} from "./mocks/AdapterMock.sol";

contract AllocateTest is BaseTest {
    using MathLib for uint256;

    address mockAdapter;
    bytes32[] public ids;

    function setUp() public override {
        super.setUp();

        mockAdapter = address(new AdapterMock(address(vault)));

        deal(address(underlyingToken), address(this), type(uint256).max);
        underlyingToken.approve(address(vault), type(uint256).max);

        vm.prank(curator);
        vault.submit(abi.encodeCall(IVaultV2.setIsAdapter, (mockAdapter, true)));
        vault.setIsAdapter(mockAdapter, true);

        ids = new bytes32[](2);
        ids[0] = keccak256("id-0");
        ids[1] = keccak256("id-1");
    }

    function testAllocate(bytes memory data, uint256 assets, address rdm, uint256 absoluteCap) public {
        vm.assume(rdm != address(allocator));
        vm.assume(rdm != address(vault));
        assets = bound(assets, 1, type(uint128).max);
        absoluteCap = bound(absoluteCap, assets, type(uint128).max);

        // Setup.
        vault.deposit(assets, address(this));
        assertEq(underlyingToken.balanceOf(address(vault)), assets, "Initial vault balance incorrect");
        assertEq(underlyingToken.balanceOf(mockAdapter), 0, "Initial adapter balance incorrect");
        assertEq(vault.allocation(keccak256("id-0")), 0, "Initial allocation incorrect");
        assertEq(vault.allocation(keccak256("id-1")), 0, "Initial allocation incorrect");

        // Access control.
        vm.prank(rdm);
        vm.expectRevert(ErrorsLib.Unauthorized.selector);
        vault.allocate(mockAdapter, data, assets);
        vm.prank(address(vault));
        vault.allocate(mockAdapter, hex"", 0);
        vm.prank(allocator);
        vault.allocate(mockAdapter, hex"", 0);

        // Can't allocate if not adapter.
        vm.prank(allocator);
        vm.expectRevert(ErrorsLib.NotAdapter.selector);
        vault.allocate(address(this), data, assets);

        // Absolute cap check.
        increaseAbsoluteCap("id-0", assets - 1);
        increaseAbsoluteCap("id-1", assets - 1);
        vm.expectRevert(ErrorsLib.AbsoluteCapExceeded.selector);
        vm.prank(allocator);
        vault.allocate(mockAdapter, data, assets);

        // Relative cap check fails on 0 cap.
        increaseAbsoluteCap("id-0", assets);
        increaseAbsoluteCap("id-1", assets);
        vm.expectRevert(ErrorsLib.RelativeCapExceeded.selector);
        vm.prank(allocator);
        vault.allocate(mockAdapter, data, assets);

        // Relative cap check fails on non-WAD cap.
        increaseRelativeCap("id-0", WAD - 1);
        increaseRelativeCap("id-1", WAD - 1);
        vm.expectRevert(ErrorsLib.RelativeCapExceeded.selector);
        vm.prank(allocator);
        vault.allocate(mockAdapter, data, assets);

        uint256 snapshot = vm.snapshotState();

        // Relative cap check passes on non-WAD cap.
        vm.prank(allocator);
        vault.allocate(mockAdapter, data, assets.mulDivDown(WAD - 1, WAD));

        vm.revertToState(snapshot);

        // Normal path.
        increaseRelativeCap("id-0", WAD);
        increaseRelativeCap("id-1", WAD);
        vm.prank(allocator);
        vm.expectEmit();
        emit EventsLib.Allocate(allocator, mockAdapter, assets, ids, 0);
        vault.allocate(mockAdapter, data, assets);
        assertEq(underlyingToken.balanceOf(address(vault)), 0, "Vault balance should be zero after allocation");
        assertEq(underlyingToken.balanceOf(mockAdapter), assets, "Adapter balance incorrect after allocation");
        assertEq(vault.allocation(keccak256("id-0")), assets, "Allocation incorrect after allocation");
        assertEq(vault.allocation(keccak256("id-1")), assets, "Allocation incorrect after allocation");
        assertEq(AdapterMock(mockAdapter).recordedAllocateData(), data, "Data incorrect after allocation");
        assertEq(AdapterMock(mockAdapter).recordedAllocateAssets(), assets, "Assets incorrect after allocation");
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
        vault.allocate(mockAdapter, data, 100);
    }

    function testDeallocate(bytes memory data, uint256 assetsIn, uint256 assetsOut, address rdm, uint256 absoluteCap)
        public
    {
        vm.assume(rdm != address(allocator));
        vm.assume(rdm != address(sentinel));
        vm.assume(rdm != address(vault));
        assetsIn = bound(assetsIn, 1, type(uint128).max);
        assetsOut = bound(assetsOut, 1, assetsIn);
        absoluteCap = bound(absoluteCap, assetsIn, type(uint128).max);

        // Setup.
        deal(address(underlyingToken), address(vault), assetsIn);
        increaseAbsoluteCap("id-0", assetsIn);
        increaseAbsoluteCap("id-1", assetsIn);
        increaseRelativeCap("id-0", WAD);
        increaseRelativeCap("id-1", WAD);
        vm.prank(allocator);
        vault.allocate(mockAdapter, data, assetsIn);

        // Access control.
        vm.prank(rdm);
        vm.expectRevert(ErrorsLib.Unauthorized.selector);
        vault.deallocate(mockAdapter, hex"", 0);
        vm.prank(allocator);
        vault.deallocate(mockAdapter, hex"", 0);
        vm.prank(sentinel);
        vault.deallocate(mockAdapter, hex"", 0);
        vm.prank(address(vault));
        vault.deallocate(mockAdapter, hex"", 0);

        // Can't deallocate if not adapter.
        vm.prank(allocator);
        vm.expectRevert(ErrorsLib.NotAdapter.selector);
        vault.deallocate(address(this), data, assetsOut);

        // Normal path.
        vm.prank(allocator);
        vm.expectEmit();
        emit EventsLib.Deallocate(allocator, mockAdapter, assetsOut, ids, 0);
        vault.deallocate(mockAdapter, data, assetsOut);
        assertEq(underlyingToken.balanceOf(address(vault)), assetsOut, "Vault balance incorrect after deallocation");
        assertEq(
            underlyingToken.balanceOf(mockAdapter), assetsIn - assetsOut, "Adapter balance incorrect after deallocation"
        );
        assertEq(vault.allocation(keccak256("id-0")), assetsIn - assetsOut, "Allocation incorrect after deallocation");
        assertEq(vault.allocation(keccak256("id-1")), assetsIn - assetsOut, "Allocation incorrect after deallocation");
        assertEq(AdapterMock(mockAdapter).recordedDeallocateData(), data, "Data incorrect after deallocation");
        assertEq(AdapterMock(mockAdapter).recordedDeallocateAssets(), assetsOut, "Assets incorrect after deallocation");
    }
}
