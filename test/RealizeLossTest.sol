// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Morpho Association
pragma solidity ^0.8.0;

import "./BaseTest.sol";

uint256 constant MAX_TEST_AMOUNT = 1e36;

contract MockAdapter is IAdapter {
    bytes32[] public ids;
    uint256 public loss;

    function setIds(bytes32[] memory _ids) external {
        ids = _ids;
    }

    function setLoss(uint256 _loss) external {
        loss = _loss;
    }

    function allocate(bytes memory, uint256) external view returns (bytes32[] memory, uint256) {
        return (ids, 0);
    }

    function deallocate(bytes memory, uint256) external view returns (bytes32[] memory, uint256) {
        return (ids, 0);
    }

    function realizePnL(bytes memory) external view returns (bytes32[] memory, uint256, uint256) {
        return (ids, 0, loss);
    }
}

contract RealizeLossTest is BaseTest {
    MockAdapter internal adapter;
    bytes internal idData;
    bytes32 internal id;
    bytes32[] internal expectedIds;

    function setUp() public override {
        super.setUp();

        adapter = new MockAdapter();

        vm.prank(curator);
        vault.submit(abi.encodeCall(IVaultV2.setIsAdapter, (address(adapter), true)));
        vault.setIsAdapter(address(adapter), true);

        deal(address(underlyingToken), address(this), type(uint256).max);
        underlyingToken.approve(address(vault), type(uint256).max);

        expectedIds = new bytes32[](1);
        idData = abi.encode("id");
        id = keccak256(idData);
        expectedIds[0] = id;
        adapter.setIds(expectedIds);
    }

    function testRealizeLossDirectly(uint256 deposit, uint256 expectedLoss) public {
        deposit = bound(deposit, 1, MAX_TEST_AMOUNT);
        expectedLoss = bound(expectedLoss, 1, deposit);

        vault.deposit(deposit, address(this));
        adapter.setLoss(expectedLoss);

        // Realize the loss.
        vault.realizePnL(address(adapter), hex"");
        assertEq(vault.totalAssets(), deposit - expectedLoss, "total assets should have decreased by the loss");
    }

    function testRealizeLossAllocate(uint256 deposit, uint256 expectedLoss) public {
        deposit = bound(deposit, 1, MAX_TEST_AMOUNT);
        expectedLoss = bound(expectedLoss, 1, deposit);

        vault.deposit(deposit, address(this));
        adapter.setLoss(expectedLoss);

        // Account the loss.
        vm.prank(allocator);
        vault.allocate(address(adapter), hex"", 0);

        // Realize the loss.
        vault.realizePnL(address(adapter), hex"");
        assertEq(vault.totalAssets(), deposit - expectedLoss, "total assets should have decreased by the loss");

        if (expectedLoss > 0) {
            assertTrue(vault.enterBlocked(), "enter should be blocked");

            // Cannot enter
            vm.expectRevert(ErrorsLib.EnterBlocked.selector);
            vault.deposit(0, address(this));
        }
    }

    function testRealizeLossDeallocate(uint256 deposit, uint256 expectedLoss) public {
        deposit = bound(deposit, 1, MAX_TEST_AMOUNT);
        expectedLoss = bound(expectedLoss, 1, deposit);

        vault.deposit(deposit, address(this));
        adapter.setLoss(expectedLoss);

        // Account the loss.
        vm.prank(allocator);
        vault.deallocate(address(adapter), hex"", 0);

        // Realize the loss.
        vault.realizePnL(address(adapter), hex"");
        assertEq(vault.totalAssets(), deposit - expectedLoss, "total assets should have decreased by the loss");

        if (expectedLoss > 0) {
            assertTrue(vault.enterBlocked(), "enter should be blocked");

            // Cannot enter
            vm.expectRevert(ErrorsLib.EnterBlocked.selector);
            vault.deposit(0, address(this));
        }
    }

    function testRealizeLossForceDeallocate(uint256 deposit, uint256 expectedLoss) public {
        deposit = bound(deposit, 1, MAX_TEST_AMOUNT);
        expectedLoss = bound(expectedLoss, 1, deposit);

        vault.deposit(deposit, address(this));
        adapter.setLoss(expectedLoss);

        // Account the loss.
        vm.prank(allocator);
        vault.forceDeallocate(address(adapter), hex"", 0, address(this));

        // Realize the loss.
        vault.realizePnL(address(adapter), hex"");
        assertEq(vault.totalAssets(), deposit - expectedLoss, "total assets should have decreased by the loss");

        if (expectedLoss > 0) {
            assertTrue(vault.enterBlocked(), "enter should be blocked");

            // Cannot enter
            vm.expectRevert(ErrorsLib.EnterBlocked.selector);
            vault.deposit(0, address(this));
        }
    }

    function testRealizeLossAllocationUpdate(uint256 deposit, uint256 expectedLoss) public {
        deposit = bound(deposit, 1, MAX_TEST_AMOUNT);
        expectedLoss = bound(expectedLoss, 1, deposit);

        vm.prank(curator);
        vault.submit(abi.encodeCall(IVaultV2.setIsAdapter, (address(adapter), true)));
        vault.setIsAdapter(address(adapter), true);
        vm.prank(allocator);
        vault.setLiquidityMarket(address(adapter), hex"");
        vm.prank(curator);
        vault.submit(abi.encodeCall(IVaultV2.increaseAbsoluteCap, (idData, deposit)));
        vault.increaseAbsoluteCap(idData, deposit);
        vm.prank(curator);
        vault.submit(abi.encodeCall(IVaultV2.increaseRelativeCap, (idData, WAD)));
        vault.increaseRelativeCap(idData, WAD);

        vault.deposit(deposit, address(this));
        assertEq(vault.allocation(id), deposit, "allocation should be equal to the deposit");

        adapter.setLoss(expectedLoss);

        // Realize the loss.
        vm.prank(allocator);
        vault.realizePnL(address(adapter), hex"");
        assertEq(vault.allocation(id), deposit - expectedLoss, "allocation should have decreased by the loss");
    }
}
