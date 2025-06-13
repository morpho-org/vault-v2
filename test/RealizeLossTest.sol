// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import "./BaseTest.sol";

uint256 constant MAX_TEST_AMOUNT = 1e36;

contract MockAdapter is IAdapter {
    bytes32[] public ids;
    uint256 public profit;
    uint256 public loss;

    function setIds(bytes32[] memory _ids) external {
        ids = _ids;
    }

    function setProfit(uint256 _profit) external {
        profit = _profit;
    }

    function setLoss(uint256 _loss) external {
        loss = _loss;
    }

    function allocate(bytes memory, uint256 assets) external view returns (bytes32[] memory, int256) {
        return (ids, int256(profit) + int256(assets) - int256(loss));
    }

    function deallocate(bytes memory, uint256 assets) external view returns (bytes32[] memory, int256) {
        return (ids, int256(profit) - int256(assets + loss));
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
        vault.submit(abi.encodeWithSelector(IVaultV2.setIsAdapter.selector, address(adapter), true));
        vault.setIsAdapter(address(adapter), true);

        deal(address(underlyingToken), address(this), type(uint256).max);
        underlyingToken.approve(address(vault), type(uint256).max);

        expectedIds = new bytes32[](1);
        idData = abi.encode("id");
        id = keccak256(idData);
        expectedIds[0] = id;
        adapter.setIds(expectedIds);
    }

    function testRealizeLossAllocateNoBuffer(uint256 deposit, uint256 expectedLoss) public {
        deposit = bound(deposit, 0, MAX_TEST_AMOUNT);
        expectedLoss = bound(expectedLoss, 0, deposit);

        vault.deposit(deposit, address(this));

        // Move to an adapter so the assets can be lost.
        increaseAbsoluteCap(idData, type(uint128).max);
        increaseRelativeCap(idData, WAD);
        vm.prank(allocator);
        vault.allocate(address(adapter), hex"", deposit);
        uint256 oldTotalAllocation = vault.totalAllocation();

        adapter.setLoss(expectedLoss);

        // Realize the loss.
        vm.prank(allocator);
        vault.allocate(address(adapter), hex"", 0);
        assertEq(vault.totalAssets(), deposit - expectedLoss, "total assets should have decreased by the loss");
        assertEq(
            vault.totalAllocation(),
            oldTotalAllocation - expectedLoss,
            "total allocation should have decreased by the expected loss"
        );

        if (expectedLoss > 0) {
            assertTrue(vault.enterBlocked(), "enter should be blocked");

            // Cannot enter
            vm.expectRevert(ErrorsLib.EnterBlocked.selector);
            vault.deposit(0, address(this));
        }
    }

    function testRealizeLossAllocateWithBuffer(uint256 deposit, uint256 adapterLoss, uint256 lossBuffer) public {
        deposit = bound(deposit, 0, MAX_TEST_AMOUNT);
        adapterLoss = bound(adapterLoss, 0, deposit);
        lossBuffer = bound(lossBuffer, 0, deposit);

        vault.deposit(deposit, address(this));

        // Move to an adapter so the assets can be lost.
        increaseAbsoluteCap(idData, type(uint128).max);
        increaseRelativeCap(idData, WAD);
        vm.prank(allocator);
        vault.allocate(address(adapter), hex"", deposit);
        uint256 oldTotalAllocation = vault.totalAllocation();

        writeTotalAllocation(oldTotalAllocation + lossBuffer);

        adapter.setLoss(adapterLoss);

        // Realize the loss.
        vm.prank(allocator);
        vault.allocate(address(adapter), hex"", 0);

        uint256 expectedLoss = lossBuffer > adapterLoss ? 0 : adapterLoss - lossBuffer;
        assertEq(vault.totalAssets(), deposit - expectedLoss, "total assets should have decreased by the expected loss");
        assertEq(
            vault.totalAllocation(),
            oldTotalAllocation + lossBuffer - adapterLoss,
            "total allocation should have decreased by the adapter loss"
        );

        if (expectedLoss > 0) {
            assertTrue(vault.enterBlocked(), "enter should be blocked");

            // Cannot enter
            vm.expectRevert(ErrorsLib.EnterBlocked.selector);
            vault.deposit(0, address(this));
        }
    }

    function testRealizeLossDeallocateNoBuffer(uint256 deposit, uint256 expectedLoss) public {
        deposit = bound(deposit, 1, MAX_TEST_AMOUNT);
        expectedLoss = bound(expectedLoss, 0, deposit);

        vault.deposit(deposit, address(this));

        vm.prank(curator);
        vault.submit(abi.encodeCall(IVaultV2.increaseAbsoluteCap, (idData, deposit)));
        vault.increaseAbsoluteCap(idData, deposit);

        vm.prank(curator);
        vault.submit(abi.encodeWithSelector(IVaultV2.increaseRelativeCap.selector, idData, WAD));
        vault.increaseRelativeCap(idData, WAD);

        vm.prank(allocator);
        vault.allocate(address(adapter), "", deposit);

        adapter.setLoss(expectedLoss);

        // Realize the loss.
        vm.prank(allocator);
        vault.deallocate(address(adapter), hex"", 0);
        assertEq(vault.totalAssets(), deposit - expectedLoss, "total assets should have decreased by the loss");

        if (expectedLoss > 0) {
            assertTrue(vault.enterBlocked(), "enter should be blocked");

            // Cannot enter
            vm.expectRevert(ErrorsLib.EnterBlocked.selector);
            vault.deposit(0, address(this));
        }
    }

    function testRealizeLossDeallocateWithBuffer(uint256 deposit, uint256 adapterLoss, uint256 lossBuffer) public {
        deposit = bound(deposit, 1, MAX_TEST_AMOUNT);
        adapterLoss = bound(adapterLoss, 0, deposit);
        lossBuffer = bound(lossBuffer, 0, deposit);

        vault.deposit(deposit, address(this));

        vm.prank(curator);
        vault.submit(abi.encodeCall(IVaultV2.increaseAbsoluteCap, (idData, deposit)));
        vault.increaseAbsoluteCap(idData, deposit);

        vm.prank(curator);
        vault.submit(abi.encodeWithSelector(IVaultV2.increaseRelativeCap.selector, idData, WAD));
        vault.increaseRelativeCap(idData, WAD);

        vm.prank(allocator);
        vault.allocate(address(adapter), "", deposit);
        uint256 oldTotalAllocation = vault.totalAllocation();

        writeTotalAllocation(oldTotalAllocation + lossBuffer);

        adapter.setLoss(adapterLoss);

        // Realize the loss.
        vm.prank(allocator);
        vault.deallocate(address(adapter), hex"", 0);

        uint256 expectedLoss = lossBuffer > adapterLoss ? 0 : adapterLoss - lossBuffer;
        assertEq(vault.totalAssets(), deposit - expectedLoss, "total assets should have decreased by the expected loss");
        assertEq(
            vault.totalAllocation(),
            oldTotalAllocation + lossBuffer - adapterLoss,
            "total allocation should have decreased by the adapter loss"
        );

        if (expectedLoss > 0) {
            assertTrue(vault.enterBlocked(), "enter should be blocked");

            // Cannot enter
            vm.expectRevert(ErrorsLib.EnterBlocked.selector);
            vault.deposit(0, address(this));
        }
    }

    function testRealizeLossForceDeallocateNoBuffer(uint256 deposit, uint256 expectedLoss) public {
        deposit = bound(deposit, 1, MAX_TEST_AMOUNT);
        expectedLoss = bound(expectedLoss, 0, deposit);

        vault.deposit(deposit, address(this));

        vm.prank(curator);
        vault.submit(abi.encodeCall(IVaultV2.increaseAbsoluteCap, (idData, deposit)));
        vault.increaseAbsoluteCap(idData, deposit);

        vm.prank(curator);
        vault.submit(abi.encodeWithSelector(IVaultV2.increaseRelativeCap.selector, idData, WAD));
        vault.increaseRelativeCap(idData, WAD);

        vm.prank(allocator);
        vault.allocate(address(adapter), "", deposit);

        adapter.setLoss(expectedLoss);

        // Realize the loss.
        vm.prank(allocator);
        vault.forceDeallocate(address(adapter), hex"", 0, address(this));
        assertEq(vault.totalAssets(), deposit - expectedLoss, "total assets should have decreased by the loss");

        if (expectedLoss > 0) {
            assertTrue(vault.enterBlocked(), "enter should be blocked");

            // Cannot enter
            vm.expectRevert(ErrorsLib.EnterBlocked.selector);
            vault.deposit(0, address(this));
        }
    }

    function testRealizeLossForceDeallocateWithBuffer(uint256 deposit, uint256 adapterLoss, uint256 lossBuffer)
        public
    {
        deposit = bound(deposit, 1, MAX_TEST_AMOUNT);
        adapterLoss = bound(adapterLoss, 0, deposit);
        lossBuffer = bound(lossBuffer, 0, deposit);

        vault.deposit(deposit, address(this));

        vm.prank(curator);
        vault.submit(abi.encodeCall(IVaultV2.increaseAbsoluteCap, (idData, deposit)));
        vault.increaseAbsoluteCap(idData, deposit);

        vm.prank(curator);
        vault.submit(abi.encodeWithSelector(IVaultV2.increaseRelativeCap.selector, idData, WAD));
        vault.increaseRelativeCap(idData, WAD);

        vm.prank(allocator);
        vault.allocate(address(adapter), "", deposit);
        uint256 oldTotalAllocation = vault.totalAllocation();

        writeTotalAllocation(oldTotalAllocation + lossBuffer);

        adapter.setLoss(adapterLoss);

        // Realize the loss.
        vm.prank(allocator);
        vault.forceDeallocate(address(adapter), hex"", 0, address(this));

        uint256 expectedLoss = lossBuffer > adapterLoss ? 0 : adapterLoss - lossBuffer;
        assertEq(vault.totalAssets(), deposit - expectedLoss, "total assets should have decreased by the expected loss");
        assertEq(
            vault.totalAllocation(),
            oldTotalAllocation + lossBuffer - adapterLoss,
            "total allocation should have decreased by the adapter loss"
        );

        if (expectedLoss > 0) {
            assertTrue(vault.enterBlocked(), "enter should be blocked");

            // Cannot enter
            vm.expectRevert(ErrorsLib.EnterBlocked.selector);
            vault.deposit(0, address(this));
        }
    }

    function testRealizeLossAllocationUpdate(uint256 deposit, uint256 expectedLoss) public {
        deposit = bound(deposit, 0, MAX_TEST_AMOUNT);
        expectedLoss = bound(expectedLoss, 0, deposit);

        vm.prank(curator);
        vault.submit(abi.encodeWithSelector(IVaultV2.setIsAdapter.selector, address(adapter), true));
        vault.setIsAdapter(address(adapter), true);
        vm.prank(allocator);
        vault.setLiquidityMarket(address(adapter), hex"");
        vm.prank(curator);
        vault.submit(abi.encodeWithSelector(IVaultV2.increaseAbsoluteCap.selector, idData, deposit));
        vault.increaseAbsoluteCap(idData, deposit);
        vm.prank(curator);
        vault.submit(abi.encodeWithSelector(IVaultV2.increaseRelativeCap.selector, idData, WAD));
        vault.increaseRelativeCap(idData, WAD);

        vault.deposit(deposit, address(this));
        assertEq(vault.allocation(id), deposit, "allocation should be equal to the deposit");

        adapter.setLoss(expectedLoss);

        // Realize the loss.
        vm.prank(allocator);
        vault.allocate(address(adapter), hex"", 0);
        assertEq(vault.allocation(id), deposit - expectedLoss, "allocation should have decreased by the loss");
    }
}
