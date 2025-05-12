// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import "./BaseTest.sol";

uint256 constant MAX_TEST_AMOUNT = 1e36;

contract MockAdapter is IAdapter {
    uint256 public loss;
    bytes32[] public ids;

    function setLoss(uint256 _loss) external {
        loss = _loss;
    }

    function setIds(bytes32[] memory _ids) external {
        ids = _ids;
    }

    function allocate(bytes memory, uint256) external view returns (bytes32[] memory) {
        return ids;
    }

    function deallocate(bytes memory, uint256) external view returns (bytes32[] memory) {}

    function realizeLoss(bytes memory) external view returns (uint256, bytes32[] memory) {
        return (loss, ids);
    }
}

contract RealizeLossTest is BaseTest {
    MockAdapter internal adapter;

    function setUp() public override {
        super.setUp();

        adapter = new MockAdapter();

        vm.prank(curator);
        vault.submit(abi.encodeWithSelector(IVaultV2.setIsAdapter.selector, address(adapter), true));
        vault.setIsAdapter(address(adapter), true);

        deal(address(underlyingToken), address(this), type(uint256).max);
        underlyingToken.approve(address(vault), type(uint256).max);
    }

    function testAccountLossAccessControl(address rdm) public {
        vm.assume(rdm != curator);
        vm.expectRevert(ErrorsLib.Unauthorized.selector);
        vm.prank(rdm);
        vault.accountLoss(address(adapter), hex"");
    }

    function testAccountLossNotAdapter(address rdm) public {
        vm.assume(rdm != address(adapter));
        vm.expectRevert(ErrorsLib.NotAdapter.selector);
        vm.prank(curator);
        vault.accountLoss(address(rdm), hex"");
    }

    function testRealizeLoss(uint256 deposit, uint256 loss) public {
        deposit = bound(deposit, 0, MAX_TEST_AMOUNT);
        loss = bound(loss, 0, MAX_TEST_AMOUNT);

        uint256 realLoss = deposit > loss ? loss : deposit;

        vault.deposit(deposit, address(this));

        // Account the loss.
        adapter.setLoss(loss);
        vm.prank(curator);
        vault.accountLoss(address(adapter), hex"");
        assertEq(vault.lossToRealize(), loss, "loss to realize should be set");
        assertEq(vault.totalAssets(), deposit, "total assets should not change during the block");

        // Accrue interest in same block doesn't change anything.
        vault.accrueInterest();
        assertEq(vault.lossToRealize(), loss, "loss to realize should be set");
        assertEq(vault.totalAssets(), deposit, "total assets should not change during the block");

        // Accrue interest after the block.
        vm.warp(vm.getBlockTimestamp() + 1);
        vault.accrueInterest();
        assertEq(vault.lossToRealize(), 0, "loss to realize should be set to 0");
        assertEq(vault.totalAssets(), deposit - realLoss, "total assets should decrease by the loss");
    }

    function testRealizeLossIds(uint256 deposit, uint256 loss) public {
        deposit = bound(deposit, 0, MAX_TEST_AMOUNT);
        loss = bound(loss, 0, deposit);

        bytes32[] memory ids = new bytes32[](1);
        bytes memory idData = abi.encode("id");
        bytes32 id = keccak256(idData);
        ids[0] = id;

        vault.deposit(deposit, address(this));
        adapter.setIds(ids);
        adapter.setLoss(loss);

        // Allocate into id.
        vm.prank(curator);
        vault.submit(abi.encodeWithSelector(vault.increaseAbsoluteCap.selector, idData, type(uint256).max));
        vault.increaseAbsoluteCap(idData, type(uint256).max);
        vm.prank(allocator);
        vault.reallocateFromIdle(address(adapter), hex"", deposit);
        assertEq(vault.allocation(id), deposit, "allocation should be set");

        // Account the loss.
        vm.prank(curator);
        vault.accountLoss(address(adapter), hex"");
        assertEq(vault.allocation(id), deposit - loss, "allocation should have decreased by the loss");
    }
}
