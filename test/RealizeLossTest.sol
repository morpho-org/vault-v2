// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Morpho Association
pragma solidity ^0.8.0;

import "./BaseTest.sol";

struct Call {
    address target;
    bytes data;
}

contract RealizeLossTest is BaseTest {
    AdapterMock internal adapter;
    uint256 MAX_TEST_AMOUNT;

    function setUp() public override {
        super.setUp();

        MAX_TEST_AMOUNT = 10 ** min(18 + underlyingToken.decimals(), 36);

        adapter = new AdapterMock(address(vault));

        vm.prank(curator);
        vault.submit(abi.encodeCall(IVaultV2.addAdapter, (address(adapter))));
        vault.addAdapter(address(adapter));

        deal(address(underlyingToken), address(this), type(uint256).max);
        underlyingToken.approve(address(vault), type(uint256).max);

        increaseAbsoluteCap(expectedIdData[0], type(uint128).max);
        increaseAbsoluteCap(expectedIdData[1], type(uint128).max);
        increaseRelativeCap(expectedIdData[0], WAD);
        increaseRelativeCap(expectedIdData[1], WAD);
    }

    /// forge-config: default.isolate = true
    function testRealizeLoss(uint256 deposit, uint256 expectedLoss) public {
        deposit = bound(deposit, 1, MAX_TEST_AMOUNT);
        expectedLoss = bound(expectedLoss, 1, deposit);

        vault.deposit(deposit, address(this));
        vm.prank(allocator);
        vault.allocate(address(adapter), hex"", deposit);
        adapter.setLoss(expectedLoss);

        // Realize the loss.
        vm.expectEmit();
        emit EventsLib.AccrueInterest(deposit, deposit - expectedLoss, 0, 0);
        vault.accrueInterest();
        assertEq(vault.totalAssets(), deposit - expectedLoss, "total assets should have decreased by the loss");
    }

    /// forge-config: default.isolate = true
    function testTouchThenLoss(uint256 deposit, uint256 expectedLoss) public {
        deposit = bound(deposit, 1, MAX_TEST_AMOUNT);
        expectedLoss = bound(expectedLoss, 1, deposit);

        vault.deposit(deposit, address(this));
        vm.prank(allocator);
        vault.allocate(address(adapter), hex"", deposit);

        Call[] memory calls = new Call[](3);
        calls[0] = Call(address(vault), abi.encodeCall(IVaultV2.accrueInterest, ()));
        calls[1] = Call(address(adapter), abi.encodeCall(AdapterMock.setLoss, (expectedLoss)));
        calls[2] = Call(address(vault), abi.encodeCall(IERC4626.totalAssets, ()));
        bytes[] memory results = this.multicall(calls);
        uint256 totalAssets = abi.decode(results[2], (uint256));
        assertEq(totalAssets, deposit, "total assets should not have changed");
    }

    /// forge-config: default.isolate = true
    function testLossThenTouch(uint256 deposit, uint256 expectedLoss) public {
        deposit = bound(deposit, 1, MAX_TEST_AMOUNT);
        expectedLoss = bound(expectedLoss, 1, deposit);

        vault.deposit(deposit, address(this));
        vm.prank(allocator);
        vault.allocate(address(adapter), hex"", deposit);

        Call[] memory calls = new Call[](2);
        calls[0] = Call(address(adapter), abi.encodeCall(AdapterMock.setLoss, (expectedLoss)));
        calls[1] = Call(address(vault), abi.encodeCall(IERC4626.totalAssets, ()));
        bytes[] memory results = this.multicall(calls);
        uint256 totalAssets = abi.decode(results[1], (uint256));
        assertEq(totalAssets, deposit - expectedLoss, "total assets should have decreased by the loss");
    }

    function testAllocationLossAllocate(uint256 deposit, uint256 expectedLoss) public {
        deposit = bound(deposit, 1, MAX_TEST_AMOUNT);
        expectedLoss = bound(expectedLoss, 1, deposit);

        vm.prank(curator);
        vault.submit(abi.encodeCall(IVaultV2.addAdapter, (address(adapter))));
        vault.addAdapter(address(adapter));
        vm.prank(allocator);
        vault.setLiquidityAdapterAndData(address(adapter), hex"");

        vault.deposit(deposit, address(this));
        adapter.setLoss(expectedLoss);

        // Realize the loss.
        vm.prank(allocator);
        vault.allocate(address(adapter), hex"", 0); // TODO: with an amount.
        assertEq(
            vault.allocation(expectedIds[0]), deposit - expectedLoss, "allocation should have decreased by the loss"
        );
    }

    function testAllocationLossDeallocate(uint256 deposit, uint256 expectedLoss) public {
        deposit = bound(deposit, 1, MAX_TEST_AMOUNT);
        expectedLoss = bound(expectedLoss, 1, deposit);

        vm.prank(curator);
        vault.submit(abi.encodeCall(IVaultV2.addAdapter, (address(adapter))));
        vault.addAdapter(address(adapter));
        vm.prank(allocator);
        vault.setLiquidityAdapterAndData(address(adapter), hex"");

        vault.deposit(deposit, address(this));
        adapter.setLoss(expectedLoss);

        // Realize the loss.
        vm.prank(allocator);
        vault.deallocate(address(adapter), hex"", 0); // TODO: with an amount.
        assertEq(
            vault.allocation(expectedIds[0]), deposit - expectedLoss, "allocation should have decreased by the loss"
        );
    }

    function testAllocationLossForceDeallocate(uint256 deposit, uint256 expectedLoss) public {
        deposit = bound(deposit, 1, MAX_TEST_AMOUNT);
        expectedLoss = bound(expectedLoss, 1, deposit);

        vm.prank(curator);
        vault.submit(abi.encodeCall(IVaultV2.addAdapter, (address(adapter))));
        vault.addAdapter(address(adapter));
        vm.prank(allocator);
        vault.setLiquidityAdapterAndData(address(adapter), hex"");

        vault.deposit(deposit, address(this));
        adapter.setLoss(expectedLoss);

        // Realize the loss.
        vault.forceDeallocate(address(adapter), hex"", 0, address(this)); // TODO: with an amount.
        assertEq(
            vault.allocation(expectedIds[0]), deposit - expectedLoss, "allocation should have decreased by the loss"
        );
    }

    function multicall(Call[] calldata calls) external returns (bytes[] memory results) {
        results = new bytes[](calls.length);
        for (uint256 i = 0; i < calls.length; i++) {
            (bool success, bytes memory result) = calls[i].target.call(calls[i].data);
            if (!success) {
                revert(string(result));
            }
            results[i] = result;
        }
        return results;
    }
}
