// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Morpho Association
pragma solidity ^0.8.0;

import "./BaseTest.sol";

uint256 constant TEST_TIMELOCK_CAP = 3 * 365 days;

contract SettersTest is BaseTest {
    function setUp() public override {
        super.setUp();

        deal(address(underlyingToken), address(this), type(uint256).max);
        underlyingToken.approve(address(vault), type(uint256).max);
    }

    function testConstructor() public view {
        assertEq(vault.owner(), owner);
        assertEq(address(vault.asset()), address(underlyingToken));
        assertEq(address(vault.curator()), curator);
        assertTrue(vault.isAllocator(address(allocator)));
    }

    /* OWNER SETTERS */

    function testSetOwner(address rdm) public {
        vm.assume(rdm != owner);
        address newOwner = makeAddr("newOwner");

        // Access control
        vm.expectRevert(ErrorsLib.Unauthorized.selector);
        vm.prank(rdm);
        vault.setOwner(newOwner);

        // Normal path
        vm.prank(owner);
        vm.expectEmit();
        emit EventsLib.SetOwner(newOwner);
        vault.setOwner(newOwner);
        assertEq(vault.owner(), newOwner);
    }

    function testSetCurator(address rdm) public {
        vm.assume(rdm != owner);
        address newCurator = makeAddr("newCurator");

        // Access control
        vm.expectRevert(ErrorsLib.Unauthorized.selector);
        vm.prank(rdm);
        vault.setCurator(newCurator);

        // Normal path
        vm.prank(owner);
        vm.expectEmit();
        emit EventsLib.SetCurator(newCurator);
        vault.setCurator(newCurator);
        assertEq(vault.curator(), newCurator);
    }

    function testSetIsSentinel(address rdm, bool newIsSentinel) public {
        vm.assume(rdm != owner);

        // Access control
        vm.expectRevert(ErrorsLib.Unauthorized.selector);
        vm.prank(rdm);
        vault.setIsSentinel(rdm, newIsSentinel);

        // Normal path
        vm.prank(owner);
        vm.expectEmit();
        emit EventsLib.SetIsSentinel(rdm, newIsSentinel);
        vault.setIsSentinel(rdm, newIsSentinel);
        assertEq(vault.isSentinel(rdm), newIsSentinel);
    }

    function testSetName(address rdm, string memory newName) public {
        vm.assume(rdm != owner);

        // Default value
        assertEq(vault.name(), "");

        // Access control
        vm.expectRevert(ErrorsLib.Unauthorized.selector);
        vm.prank(rdm);
        vault.setName(newName);

        // Normal path
        vm.prank(owner);
        vm.expectEmit();
        emit EventsLib.SetName(newName);
        vault.setName(newName);
        assertEq(vault.name(), newName);
    }

    function testSetSymbol(address rdm, string memory newSymbol) public {
        vm.assume(rdm != owner);

        // Default value
        assertEq(vault.symbol(), "");

        // Access control
        vm.expectRevert(ErrorsLib.Unauthorized.selector);
        vm.prank(rdm);
        vault.setSymbol(newSymbol);

        // Normal path
        vm.prank(owner);
        vm.expectEmit();
        emit EventsLib.SetSymbol(newSymbol);
        vault.setSymbol(newSymbol);
        assertEq(vault.symbol(), newSymbol);
    }

    /* CURATOR SETTERS */

    function testSubmitNotDecreaseTimelock(bytes memory data, address rdm) public {
        vm.assume(rdm != curator);
        vm.assume(bytes4(data) != IVaultV2.decreaseTimelock.selector);

        // Only curator can submit
        vm.assume(rdm != curator);
        vm.expectRevert(ErrorsLib.Unauthorized.selector);
        vm.prank(rdm);
        vault.submit(data);

        // Normal path
        vm.expectEmit();
        emit EventsLib.Submit(bytes4(data), data, block.timestamp + vault.timelock(bytes4(data)));
        vm.prank(curator);
        vault.submit(data);
        assertEq(vault.executableAt(data), block.timestamp + vault.timelock(bytes4(data)));

        // Data already pending
        vm.expectRevert(ErrorsLib.DataAlreadyPending.selector);
        vm.prank(curator);
        vault.submit(data);
    }

    function testSubmitDecreaseTimelock(bytes4 selector, uint256 oldDuration, uint256 newDuration, address rdm)
        public
    {
        if (selector != IVaultV2.decreaseTimelock.selector) {
            oldDuration = bound(oldDuration, 1, TEST_TIMELOCK_CAP);
        } else {
            oldDuration = 0;
        }
        newDuration = bound(newDuration, 0, oldDuration);
        vm.assume(rdm != curator);

        bytes memory data = abi.encodeCall(IVaultV2.decreaseTimelock, (selector, newDuration));

        // Only curator can submit
        vm.assume(rdm != curator);
        vm.expectRevert(ErrorsLib.Unauthorized.selector);
        vm.prank(rdm);
        vault.submit(data);

        if (selector != IVaultV2.decreaseTimelock.selector) {
            vm.prank(curator);
            vault.submit(abi.encodeCall(IVaultV2.increaseTimelock, (selector, oldDuration)));
            vault.increaseTimelock(selector, oldDuration);
        }

        // Normal path
        vm.expectEmit();
        emit EventsLib.Submit(IVaultV2.decreaseTimelock.selector, data, block.timestamp + oldDuration);
        vm.prank(curator);
        vault.submit(data);
        assertEq(vault.executableAt(data), block.timestamp + oldDuration);

        // Data already pending
        vm.expectRevert(ErrorsLib.DataAlreadyPending.selector);
        vm.prank(curator);
        vault.submit(data);
    }

    function testRevoke(bytes memory data, address rdm) public {
        vm.assume(rdm != curator);
        vm.assume(rdm != sentinel);

        // No pending data
        vm.expectRevert(ErrorsLib.DataNotTimelocked.selector);
        vm.prank(sentinel);
        vault.revoke(data);

        // Setup
        vm.prank(curator);
        vault.submit(data);

        // Access control
        vm.expectRevert(ErrorsLib.Unauthorized.selector);
        vm.prank(rdm);
        vault.revoke(data);

        // Normal path
        uint256 snapshot = vm.snapshotState();
        vm.prank(sentinel);
        vm.expectEmit();
        emit EventsLib.Revoke(sentinel, bytes4(data), data);
        vault.revoke(data);
        assertEq(vault.executableAt(data), 0);

        // Curator can revoke as well
        vm.revertToState(snapshot);
        vm.prank(curator);
        vault.revoke(data);
        assertEq(vault.executableAt(data), 0);
    }

    function testTimelocked(uint256 timelock) public {
        timelock = bound(timelock, 1, TEST_TIMELOCK_CAP);

        // Setup.
        vm.prank(curator);
        vault.submit(abi.encodeCall(IVaultV2.increaseTimelock, (IVaultV2.setIsAllocator.selector, timelock)));
        vault.increaseTimelock(IVaultV2.setIsAllocator.selector, timelock);
        assertEq(vault.timelock(IVaultV2.setIsAllocator.selector), timelock);
        bytes memory data = abi.encodeCall(IVaultV2.setIsAllocator, (address(1), true));
        vm.prank(curator);
        vault.submit(data);
        assertEq(vault.executableAt(data), block.timestamp + timelock);

        // Timelock didn't pass.
        skip(timelock - 1);
        vm.expectRevert(ErrorsLib.TimelockNotExpired.selector);
        vault.setIsAllocator(address(1), true);

        // Normal path.
        skip(1);
        vm.expectEmit();
        emit EventsLib.Accept(IVaultV2.setIsAllocator.selector, data);
        vault.setIsAllocator(address(1), true);

        // Data not timelocked.
        vm.expectRevert(ErrorsLib.DataNotTimelocked.selector);
        vault.setIsAllocator(address(1), true);
    }

    function testSetIsAllocator(address rdm) public {
        address newAllocator = makeAddr("newAllocator");

        // Nobody can set directly
        vm.expectRevert(ErrorsLib.DataNotTimelocked.selector);
        vm.prank(rdm);
        vault.setIsAllocator(newAllocator, true);
        vm.expectRevert(ErrorsLib.DataNotTimelocked.selector);
        vm.prank(curator);
        vault.setIsAllocator(newAllocator, true);

        // Normal path
        vm.prank(curator);
        vault.submit(abi.encodeCall(IVaultV2.setIsAllocator, (newAllocator, true)));
        vm.expectEmit();
        emit EventsLib.SetIsAllocator(newAllocator, true);
        vault.setIsAllocator(newAllocator, true);
        assertTrue(vault.isAllocator(newAllocator));

        // Removal
        vm.prank(curator);
        vault.submit(abi.encodeCall(IVaultV2.setIsAllocator, (newAllocator, false)));
        vm.expectEmit();
        emit EventsLib.SetIsAllocator(newAllocator, false);
        vault.setIsAllocator(newAllocator, false);
        assertFalse(vault.isAllocator(newAllocator));
    }

    function testAddAdapterNoRegistry(address rdm) public {
        vm.assume(rdm != curator);
        address newAdapter = makeAddr("newAdapter");

        // Nobody can set directly
        vm.expectRevert(ErrorsLib.DataNotTimelocked.selector);
        vm.prank(rdm);
        vault.addAdapter(newAdapter);
        vm.expectRevert(ErrorsLib.DataNotTimelocked.selector);
        vm.prank(curator);
        vault.addAdapter(newAdapter);

        // Normal path
        vm.prank(curator);
        vault.submit(abi.encodeCall(IVaultV2.addAdapter, (newAdapter)));
        vm.expectEmit();
        emit EventsLib.AddAdapter(newAdapter);
        vault.addAdapter(newAdapter);
        assertTrue(vault.isAdapter(newAdapter));
        assertEq(vault.adaptersLength(), 1);
        assertEq(vault.adapters(0), newAdapter);
    }

    function testAddAdapterRegistry(bool isInRegistry) public {
        address newAdapter = makeAddr("newAdapter");
        address registry = makeAddr("registry");

        vm.mockCall(
            address(registry),
            abi.encodeWithSelector(IAdapterRegistry.isInRegistry.selector, newAdapter),
            abi.encode(isInRegistry)
        );

        vm.prank(curator);
        vault.submit(abi.encodeCall(IVaultV2.setAdapterRegistry, (registry)));
        vault.setAdapterRegistry(registry);

        vm.prank(curator);
        vault.submit(abi.encodeCall(IVaultV2.addAdapter, (newAdapter)));
        if (!isInRegistry) vm.expectRevert(ErrorsLib.NotInAdapterRegistry.selector);
        vault.addAdapter(newAdapter);
    }

    function testRemoveAdapter(address rdm) public {
        vm.assume(rdm != curator);
        address newAdapter = makeAddr("newAdapter");
        vm.prank(curator);
        vault.submit(abi.encodeCall(IVaultV2.addAdapter, (newAdapter)));
        vault.addAdapter(newAdapter);

        // Removal
        vm.prank(curator);
        vault.submit(abi.encodeCall(IVaultV2.removeAdapter, (newAdapter)));
        vm.expectEmit();
        emit EventsLib.RemoveAdapter(newAdapter);
        vault.removeAdapter(newAdapter);
        assertFalse(vault.isAdapter(newAdapter));
        assertEq(vault.adaptersLength(), 0);
    }

    function testIncreaseTimelock(address rdm, bytes4 selector, uint256 newTimelock) public {
        vm.assume(rdm != curator);
        newTimelock = bound(newTimelock, 0, TEST_TIMELOCK_CAP);
        vm.assume(selector != IVaultV2.decreaseTimelock.selector);

        // Nobody can set directly
        vm.expectRevert(ErrorsLib.DataNotTimelocked.selector);
        vm.prank(rdm);
        vault.increaseTimelock(selector, newTimelock);
        vm.expectRevert(ErrorsLib.DataNotTimelocked.selector);
        vm.prank(curator);
        vault.increaseTimelock(selector, newTimelock);

        // Access control
        vm.expectRevert(ErrorsLib.Unauthorized.selector);
        vm.prank(rdm);
        vault.submit(abi.encodeCall(IVaultV2.increaseTimelock, (selector, newTimelock)));

        // Normal path
        vm.prank(curator);
        vault.submit(abi.encodeCall(IVaultV2.increaseTimelock, (selector, newTimelock)));
        vm.expectEmit();
        emit EventsLib.IncreaseTimelock(selector, newTimelock);
        skip(TEST_TIMELOCK_CAP);
        vault.increaseTimelock(selector, newTimelock);
        assertEq(vault.timelock(selector), newTimelock);

        // Cannot increase decreaseTimelock's timelock
        vm.prank(curator);
        vault.submit(abi.encodeCall(IVaultV2.increaseTimelock, (IVaultV2.decreaseTimelock.selector, 1 weeks)));
        vm.expectRevert(ErrorsLib.AutomaticallyTimelocked.selector);
        vault.increaseTimelock(IVaultV2.decreaseTimelock.selector, 1 weeks);

        // Can't decrease timelock
        if (newTimelock > 0) {
            vm.prank(curator);
            vault.submit(abi.encodeCall(IVaultV2.increaseTimelock, (selector, newTimelock - 1)));
            skip(TEST_TIMELOCK_CAP);
            vm.expectRevert(ErrorsLib.TimelockNotIncreasing.selector);
            vault.increaseTimelock(selector, newTimelock - 1);
        }
    }

    function testDecreaseTimelock(address rdm, bytes4 selector, uint256 oldTimelock, uint256 newTimelock) public {
        vm.assume(rdm != curator);
        vm.assume(selector != IVaultV2.decreaseTimelock.selector);
        oldTimelock = bound(oldTimelock, 1, TEST_TIMELOCK_CAP);
        newTimelock = bound(newTimelock, 0, oldTimelock);

        vm.prank(curator);
        vault.submit(abi.encodeCall(IVaultV2.increaseTimelock, (selector, oldTimelock)));
        vault.increaseTimelock(selector, oldTimelock);

        // Nobody can set directly
        vm.expectRevert(ErrorsLib.DataNotTimelocked.selector);
        vm.prank(rdm);
        vault.decreaseTimelock(selector, newTimelock);
        vm.expectRevert(ErrorsLib.DataNotTimelocked.selector);
        vm.prank(curator);
        vault.decreaseTimelock(selector, newTimelock);

        // decreaseTimelock timelock is 0 (and meaningless)
        vm.assertEq(vault.timelock(IVaultV2.decreaseTimelock.selector), 0);

        // Can't increase timelock with decreaseTimelock
        vm.prank(curator);
        vault.submit(abi.encodeCall(IVaultV2.decreaseTimelock, (selector, oldTimelock + 1)));
        skip(oldTimelock);
        vm.expectRevert(ErrorsLib.TimelockNotDecreasing.selector);
        vault.decreaseTimelock(selector, oldTimelock + 1);

        // Normal path
        vm.prank(curator);
        vault.submit(abi.encodeCall(IVaultV2.decreaseTimelock, (selector, newTimelock)));
        skip(oldTimelock);
        vm.expectEmit();
        emit EventsLib.DecreaseTimelock(selector, newTimelock);
        vault.decreaseTimelock(selector, newTimelock);
        assertEq(vault.timelock(selector), newTimelock);

        // Cannot decrease decreaseTimelock's timelock
        vm.prank(curator);
        vault.submit(abi.encodeCall(IVaultV2.decreaseTimelock, (IVaultV2.decreaseTimelock.selector, 1 weeks)));
        vm.expectRevert(ErrorsLib.AutomaticallyTimelocked.selector);
        vault.decreaseTimelock(IVaultV2.decreaseTimelock.selector, 1 weeks);
    }

    function testAbdicateNobodyCanSetDirectly(address rdm, bytes4 selector) public {
        vm.prank(rdm);
        vm.expectRevert(ErrorsLib.DataNotTimelocked.selector);
        vault.abdicate(selector);
    }

    function testAbdicate(bytes4 selector) public {
        vm.prank(curator);
        vault.submit(abi.encodeCall(IVaultV2.abdicate, (selector)));
        vm.expectEmit();
        emit EventsLib.Abdicate(selector);
        vault.abdicate(selector);
        assertTrue(vault.abdicated(selector));
    }

    function testSetPerformanceFee(address rdm, uint256 newPerformanceFee) public {
        vm.assume(rdm != curator);
        newPerformanceFee = bound(newPerformanceFee, 1, MAX_PERFORMANCE_FEE);

        // Nobody can set directly
        vm.expectRevert(ErrorsLib.DataNotTimelocked.selector);
        vm.prank(rdm);
        vault.setPerformanceFee(newPerformanceFee);
        vm.expectRevert(ErrorsLib.DataNotTimelocked.selector);
        vm.prank(curator);
        vault.setPerformanceFee(newPerformanceFee);

        // No op works
        vm.prank(curator);
        vault.submit(abi.encodeCall(IVaultV2.setPerformanceFee, (0)));
        vault.setPerformanceFee(0);

        // Can't go over fee cap
        uint256 tooHighFee = 1 ether + 1;
        vm.prank(curator);
        vault.submit(abi.encodeCall(IVaultV2.setPerformanceFee, (tooHighFee)));
        vm.expectRevert(ErrorsLib.FeeTooHigh.selector);
        vault.setPerformanceFee(tooHighFee);

        // Fee invariant
        vm.prank(curator);
        vault.submit(abi.encodeCall(IVaultV2.setPerformanceFee, (newPerformanceFee)));
        vm.expectRevert(ErrorsLib.FeeInvariantBroken.selector);
        vault.setPerformanceFee(newPerformanceFee);

        // Normal path
        vm.prank(curator);
        vault.submit(abi.encodeCall(IVaultV2.setPerformanceFeeRecipient, (makeAddr("newPerformanceFeeRecipient"))));
        vault.setPerformanceFeeRecipient(makeAddr("newPerformanceFeeRecipient"));
        vm.expectEmit();
        emit EventsLib.SetPerformanceFee(newPerformanceFee);
        vault.setPerformanceFee(newPerformanceFee);
        assertEq(vault.performanceFee(), newPerformanceFee);
    }

    function testSetManagementFee(address rdm, uint256 newManagementFee) public {
        vm.assume(rdm != curator);
        newManagementFee = bound(newManagementFee, 1, MAX_MANAGEMENT_FEE);

        // Nobody can set directly
        vm.expectRevert(ErrorsLib.DataNotTimelocked.selector);
        vm.prank(rdm);
        vault.setManagementFee(newManagementFee);
        vm.expectRevert(ErrorsLib.DataNotTimelocked.selector);
        vm.prank(curator);
        vault.setManagementFee(newManagementFee);

        // No op works
        vm.prank(curator);
        vault.submit(abi.encodeCall(IVaultV2.setManagementFee, (0)));
        vault.setManagementFee(0);

        // Can't go over fee cap
        uint256 tooHighFee = 1 ether + 1;
        vm.prank(curator);
        vault.submit(abi.encodeCall(IVaultV2.setManagementFee, (tooHighFee)));
        vm.expectRevert(ErrorsLib.FeeTooHigh.selector);
        vault.setManagementFee(tooHighFee);

        // Fee invariant
        vm.prank(curator);
        vault.submit(abi.encodeCall(IVaultV2.setManagementFee, (newManagementFee)));
        vm.expectRevert(ErrorsLib.FeeInvariantBroken.selector);
        vault.setManagementFee(newManagementFee);

        // Normal path
        vm.prank(curator);
        vault.submit(abi.encodeCall(IVaultV2.setManagementFeeRecipient, (makeAddr("newManagementFeeRecipient"))));
        vault.setManagementFeeRecipient(makeAddr("newManagementFeeRecipient"));
        vm.expectEmit();
        emit EventsLib.SetManagementFee(newManagementFee);
        vault.setManagementFee(newManagementFee);
        assertEq(vault.managementFee(), newManagementFee);
    }

    function testSetManagementFeeLastUpdateRefresh(uint256 newManagementFee, uint48 elapsed) public {
        newManagementFee = bound(newManagementFee, 1, MAX_MANAGEMENT_FEE);

        vm.prank(curator);
        vault.submit(abi.encodeCall(IVaultV2.setManagementFeeRecipient, (makeAddr("newManagementFeeRecipient"))));
        vault.setManagementFeeRecipient(makeAddr("newManagementFeeRecipient"));

        vm.prank(curator);
        vault.submit(abi.encodeCall(IVaultV2.setManagementFee, (newManagementFee)));
        skip(elapsed);
        vault.setManagementFee(newManagementFee);
        assertEq(vault.lastUpdate(), vm.getBlockTimestamp());
    }

    function testSetManagementFeeRecipientLastUpdateRefresh(address newRecipient, uint48 elapsed) public {
        vm.prank(curator);
        vault.submit(abi.encodeCall(IVaultV2.setManagementFeeRecipient, (newRecipient)));
        skip(elapsed);
        vault.setManagementFeeRecipient(newRecipient);
        assertEq(vault.lastUpdate(), vm.getBlockTimestamp());
    }

    function testSetPerformanceFeeLastUpdateRefresh(uint256 newPerformanceFee, uint48 elapsed) public {
        newPerformanceFee = bound(newPerformanceFee, 1, MAX_PERFORMANCE_FEE);

        vm.prank(curator);
        vault.submit(abi.encodeCall(IVaultV2.setPerformanceFeeRecipient, (makeAddr("newPerformanceFeeRecipient"))));
        vault.setPerformanceFeeRecipient(makeAddr("newPerformanceFeeRecipient"));

        vm.prank(curator);
        vault.submit(abi.encodeCall(IVaultV2.setPerformanceFee, (newPerformanceFee)));
        skip(elapsed);
        vault.setPerformanceFee(newPerformanceFee);
        assertEq(vault.lastUpdate(), vm.getBlockTimestamp());
    }

    function testSetPerformanceFeeRecipientLastUpdateRefresh(address newRecipient, uint48 elapsed) public {
        vm.prank(curator);
        vault.submit(abi.encodeCall(IVaultV2.setPerformanceFeeRecipient, (newRecipient)));
        skip(elapsed);
        vault.setPerformanceFeeRecipient(newRecipient);
        assertEq(vault.lastUpdate(), vm.getBlockTimestamp());
    }

    function testSetPerformanceFeeRecipient(address rdm, address newPerformanceFeeRecipient) public {
        vm.assume(rdm != curator);
        vm.assume(newPerformanceFeeRecipient != address(0));

        // Nobody can set directly
        vm.expectRevert(ErrorsLib.DataNotTimelocked.selector);
        vm.prank(rdm);
        vault.setPerformanceFeeRecipient(newPerformanceFeeRecipient);
        vm.expectRevert(ErrorsLib.DataNotTimelocked.selector);
        vm.prank(curator);
        vault.setPerformanceFeeRecipient(newPerformanceFeeRecipient);

        // Normal path
        vm.prank(curator);
        vault.submit(abi.encodeCall(IVaultV2.setPerformanceFeeRecipient, (newPerformanceFeeRecipient)));
        vm.expectEmit();
        emit EventsLib.SetPerformanceFeeRecipient(newPerformanceFeeRecipient);
        vault.setPerformanceFeeRecipient(newPerformanceFeeRecipient);
        assertEq(vault.performanceFeeRecipient(), newPerformanceFeeRecipient);

        // Fee invariant
        uint256 newPerformanceFee = 0.05 ether;
        vm.prank(curator);
        vault.submit(abi.encodeCall(IVaultV2.setPerformanceFee, (newPerformanceFee)));
        vault.setPerformanceFee(newPerformanceFee);
        vm.prank(curator);
        vault.submit(abi.encodeCall(IVaultV2.setPerformanceFeeRecipient, (address(0))));
        vm.expectRevert(ErrorsLib.FeeInvariantBroken.selector);
        vault.setPerformanceFeeRecipient(address(0));
    }

    function testSetManagementFeeRecipient(address rdm, address newManagementFeeRecipient) public {
        vm.assume(rdm != curator);
        vm.assume(newManagementFeeRecipient != address(0));

        // Nobody can set directly
        vm.expectRevert(ErrorsLib.DataNotTimelocked.selector);
        vm.prank(rdm);
        vault.setManagementFeeRecipient(newManagementFeeRecipient);
        vm.expectRevert(ErrorsLib.DataNotTimelocked.selector);
        vm.prank(curator);
        vault.setManagementFeeRecipient(newManagementFeeRecipient);

        // Normal path
        vm.prank(curator);
        vault.submit(abi.encodeCall(IVaultV2.setManagementFeeRecipient, (newManagementFeeRecipient)));
        vm.expectEmit();
        emit EventsLib.SetManagementFeeRecipient(newManagementFeeRecipient);
        vault.setManagementFeeRecipient(newManagementFeeRecipient);
        assertEq(vault.managementFeeRecipient(), newManagementFeeRecipient);

        // Fee invariant
        uint256 newManagementFee = 0.01 ether / uint256(365 days);
        vm.prank(curator);
        vault.submit(abi.encodeCall(IVaultV2.setManagementFee, (newManagementFee)));
        vault.setManagementFee(newManagementFee);
        vm.prank(curator);
        vault.submit(abi.encodeCall(IVaultV2.setManagementFeeRecipient, (address(0))));
        vm.expectRevert(ErrorsLib.FeeInvariantBroken.selector);
        vault.setManagementFeeRecipient(address(0));
    }

    function testIncreaseAbsoluteCap(address rdm, bytes memory idData, uint256 newAbsoluteCap) public {
        vm.assume(rdm != curator);
        newAbsoluteCap = bound(newAbsoluteCap, 0, type(uint128).max);
        bytes32 id = keccak256(idData);

        // Nobody can set directly
        vm.expectRevert(ErrorsLib.DataNotTimelocked.selector);
        vm.prank(rdm);
        vault.increaseAbsoluteCap(idData, newAbsoluteCap);
        vm.expectRevert(ErrorsLib.DataNotTimelocked.selector);
        vm.prank(curator);
        vault.increaseAbsoluteCap(idData, newAbsoluteCap);

        // Normal path
        vm.prank(curator);
        vault.submit(abi.encodeCall(IVaultV2.increaseAbsoluteCap, (idData, newAbsoluteCap)));
        vm.expectEmit();
        emit EventsLib.IncreaseAbsoluteCap(id, idData, newAbsoluteCap);
        vault.increaseAbsoluteCap(idData, newAbsoluteCap);
        assertEq(vault.absoluteCap(id), newAbsoluteCap);

        // Can't decrease absolute cap
        if (newAbsoluteCap > 0) {
            vm.prank(curator);
            vault.submit(abi.encodeCall(IVaultV2.increaseAbsoluteCap, (idData, newAbsoluteCap - 1)));
            vm.expectRevert(ErrorsLib.AbsoluteCapNotIncreasing.selector);
            vault.increaseAbsoluteCap(idData, newAbsoluteCap - 1);
        }
    }

    function testIncreaseAbsoluteCapOverflow(bytes memory idData, uint256 newAbsoluteCap) public {
        newAbsoluteCap = bound(newAbsoluteCap, uint256(type(uint128).max) + 1, type(uint256).max);
        vm.prank(curator);
        vault.submit(abi.encodeCall(IVaultV2.increaseAbsoluteCap, (idData, newAbsoluteCap)));
        vm.expectRevert(ErrorsLib.CastOverflow.selector);
        vault.increaseAbsoluteCap(idData, newAbsoluteCap);
    }

    function testDecreaseAbsoluteCap(address rdm, bytes memory idData, uint256 oldAbsoluteCap, uint256 newAbsoluteCap)
        public
    {
        vm.assume(rdm != curator && rdm != sentinel);
        vm.assume(newAbsoluteCap >= 0);
        vm.assume(idData.length > 0);
        newAbsoluteCap = bound(newAbsoluteCap, 0, type(uint128).max - 1);
        oldAbsoluteCap = bound(oldAbsoluteCap, newAbsoluteCap, type(uint128).max - 1);
        bytes32 id = keccak256(idData);

        vm.prank(curator);
        vault.submit(abi.encodeCall(IVaultV2.increaseAbsoluteCap, (idData, oldAbsoluteCap)));
        vault.increaseAbsoluteCap(idData, oldAbsoluteCap);

        // Access control
        vm.expectRevert(ErrorsLib.Unauthorized.selector);
        vm.prank(rdm);
        vault.decreaseAbsoluteCap(idData, newAbsoluteCap);

        // Can't increase absolute cap
        vm.expectRevert(ErrorsLib.AbsoluteCapNotDecreasing.selector);
        vm.prank(curator);
        vault.decreaseAbsoluteCap(idData, oldAbsoluteCap + 1);

        // Normal path
        vm.expectEmit();
        emit EventsLib.DecreaseAbsoluteCap(curator, id, idData, newAbsoluteCap);
        vm.prank(curator);
        vault.decreaseAbsoluteCap(idData, newAbsoluteCap);
        assertEq(vault.absoluteCap(id), newAbsoluteCap);
    }

    function testIncreaseRelativeCap(address rdm, bytes memory idData, uint256 oldRelativeCap, uint256 newRelativeCap)
        public
    {
        oldRelativeCap = bound(oldRelativeCap, 1, WAD - 1);
        newRelativeCap = bound(newRelativeCap, oldRelativeCap, WAD - 1);
        bytes32 id = keccak256(idData);

        vm.prank(curator);
        vault.submit(abi.encodeCall(IVaultV2.increaseRelativeCap, (idData, oldRelativeCap)));
        vault.increaseRelativeCap(idData, oldRelativeCap);

        // Nobody can set directly
        vm.expectRevert(ErrorsLib.DataNotTimelocked.selector);
        vm.prank(rdm);
        vault.increaseRelativeCap(idData, newRelativeCap);
        vm.expectRevert(ErrorsLib.DataNotTimelocked.selector);
        vm.prank(curator);
        vault.increaseRelativeCap(idData, newRelativeCap);

        // Can't increase relative cap above 1
        vm.prank(curator);
        vault.submit(abi.encodeCall(IVaultV2.increaseRelativeCap, (idData, WAD + 1)));
        vm.expectRevert(ErrorsLib.RelativeCapAboveOne.selector);
        vault.increaseRelativeCap(idData, WAD + 1);

        // Normal path
        vm.prank(curator);
        vault.submit(abi.encodeCall(IVaultV2.increaseRelativeCap, (idData, newRelativeCap)));
        vm.expectEmit();
        emit EventsLib.IncreaseRelativeCap(id, idData, newRelativeCap);
        vault.increaseRelativeCap(idData, newRelativeCap);
        assertEq(vault.relativeCap(id), newRelativeCap);

        // Can't decrease relative cap
        if (newRelativeCap < WAD) {
            vm.prank(curator);
            vault.submit(abi.encodeCall(IVaultV2.increaseRelativeCap, (idData, newRelativeCap - 1)));
            vm.expectRevert(ErrorsLib.RelativeCapNotIncreasing.selector);
            vault.increaseRelativeCap(idData, newRelativeCap - 1);
        }
    }

    function testDecreaseRelativeCapSequence(
        address rdm,
        bytes memory idData,
        uint256 oldRelativeCap,
        uint256 newRelativeCap
    ) public {
        vm.assume(rdm != curator);
        vm.assume(rdm != sentinel);
        bytes32 id = keccak256(idData);
        oldRelativeCap = bound(oldRelativeCap, 1, WAD);
        newRelativeCap = bound(newRelativeCap, 0, oldRelativeCap);

        vm.prank(curator);
        vault.submit(abi.encodeCall(IVaultV2.increaseRelativeCap, (idData, oldRelativeCap)));
        vault.increaseRelativeCap(idData, oldRelativeCap);

        // Access control
        vm.expectRevert(ErrorsLib.Unauthorized.selector);
        vm.prank(rdm);
        vault.decreaseRelativeCap(idData, newRelativeCap);

        // Normal path
        vm.prank(curator);
        vm.expectEmit();
        emit EventsLib.DecreaseRelativeCap(curator, id, idData, newRelativeCap);
        vault.decreaseRelativeCap(idData, newRelativeCap);
        assertEq(vault.relativeCap(id), newRelativeCap);

        // Can't increase relative cap
        vm.prank(curator);
        vm.expectRevert(ErrorsLib.RelativeCapNotDecreasing.selector);
        vault.decreaseRelativeCap(idData, newRelativeCap + 1);
    }

    function testSetMaxRateCantSetDirectly(address rdm) public {
        vm.assume(rdm != allocator);
        vm.expectRevert(ErrorsLib.Unauthorized.selector);
        vm.prank(rdm);
        vault.setMaxRate(MAX_MAX_RATE);
    }

    function testSetMaxRateTooHigh(uint256 newMaxRate) public {
        newMaxRate = bound(newMaxRate, MAX_MAX_RATE + 1, type(uint256).max);
        vm.prank(allocator);
        vm.expectRevert(ErrorsLib.MaxRateTooHigh.selector);
        vault.setMaxRate(newMaxRate);
    }

    function testSetMaxRate(uint256 newMaxRate) public {
        newMaxRate = bound(newMaxRate, 0, MAX_MAX_RATE);
        vm.prank(allocator);
        vm.expectEmit();
        emit EventsLib.SetMaxRate(newMaxRate);
        vault.setMaxRate(newMaxRate);
        assertEq(vault.maxRate(), newMaxRate);
    }

    function testSetForceDeallocatePenalty(address rdm, uint256 newForceDeallocatePenalty) public {
        vm.assume(rdm != curator);
        newForceDeallocatePenalty = bound(newForceDeallocatePenalty, 0, MAX_FORCE_DEALLOCATE_PENALTY);

        // Setup.
        address adapter = makeAddr("adapter");
        vm.prank(curator);
        vault.submit(abi.encodeCall(IVaultV2.addAdapter, (adapter)));
        vault.addAdapter(adapter);

        // Nobody can set directly
        vm.expectRevert(ErrorsLib.DataNotTimelocked.selector);
        vm.prank(rdm);
        vault.setForceDeallocatePenalty(adapter, newForceDeallocatePenalty);
        vm.expectRevert(ErrorsLib.DataNotTimelocked.selector);
        vm.prank(curator);
        vault.setForceDeallocatePenalty(adapter, newForceDeallocatePenalty);

        // Normal path
        vm.prank(curator);
        vault.submit(abi.encodeCall(IVaultV2.setForceDeallocatePenalty, (adapter, newForceDeallocatePenalty)));
        vm.expectEmit();
        emit EventsLib.SetForceDeallocatePenalty(adapter, newForceDeallocatePenalty);
        vault.setForceDeallocatePenalty(adapter, newForceDeallocatePenalty);
        assertEq(vault.forceDeallocatePenalty(adapter), newForceDeallocatePenalty);

        // Can't set fee above cap
        uint256 tooHighPenalty = MAX_FORCE_DEALLOCATE_PENALTY + 1;
        vm.prank(curator);
        vault.submit(abi.encodeCall(IVaultV2.setForceDeallocatePenalty, (adapter, tooHighPenalty)));
        vm.expectRevert(ErrorsLib.PenaltyTooHigh.selector);
        vault.setForceDeallocatePenalty(adapter, tooHighPenalty);
    }

    function testSetReceiveSharesGate(address rdm) public {
        vm.assume(rdm != curator);
        address newReceiveSharesGate = makeAddr("newReceiveSharesGate");

        // Nobody can set directly
        vm.expectRevert(ErrorsLib.DataNotTimelocked.selector);
        vm.prank(rdm);
        vault.setReceiveSharesGate(newReceiveSharesGate);
        vm.expectRevert(ErrorsLib.DataNotTimelocked.selector);
        vm.prank(curator);
        vault.setReceiveSharesGate(newReceiveSharesGate);

        // Normal path
        vm.prank(curator);
        vault.submit(abi.encodeCall(IVaultV2.setReceiveSharesGate, (newReceiveSharesGate)));
        vm.expectEmit();
        emit EventsLib.SetReceiveSharesGate(newReceiveSharesGate);
        vault.setReceiveSharesGate(newReceiveSharesGate);
        assertEq(vault.receiveSharesGate(), newReceiveSharesGate);
    }

    function testSetSendSharesGate(address rdm) public {
        vm.assume(rdm != curator);
        address newSendSharesGate = makeAddr("newSendSharesGate");

        // Nobody can set directly
        vm.expectRevert(ErrorsLib.DataNotTimelocked.selector);
        vm.prank(rdm);
        vault.setSendSharesGate(newSendSharesGate);

        // Normal path
        vm.prank(curator);
        vault.submit(abi.encodeCall(IVaultV2.setSendSharesGate, (newSendSharesGate)));
        vm.expectEmit();
        emit EventsLib.SetSendSharesGate(newSendSharesGate);
        vault.setSendSharesGate(newSendSharesGate);
        assertEq(vault.sendSharesGate(), newSendSharesGate);
    }

    function testSetReceiveAssetsGate(address rdm) public {
        vm.assume(rdm != curator);
        address newReceiveAssetsGate = makeAddr("newReceiveAssetsGate");

        // Nobody can set directly
        vm.expectRevert(ErrorsLib.DataNotTimelocked.selector);
        vm.prank(rdm);
        vault.setReceiveAssetsGate(newReceiveAssetsGate);
        vm.expectRevert(ErrorsLib.DataNotTimelocked.selector);
        vm.prank(curator);
        vault.setReceiveAssetsGate(newReceiveAssetsGate);

        // Normal path
        vm.prank(curator);
        vault.submit(abi.encodeCall(IVaultV2.setReceiveAssetsGate, (newReceiveAssetsGate)));
        vm.expectEmit();
        emit EventsLib.SetReceiveAssetsGate(newReceiveAssetsGate);
        vault.setReceiveAssetsGate(newReceiveAssetsGate);
        assertEq(vault.receiveAssetsGate(), newReceiveAssetsGate);
    }

    function testSetSendAssetsGate(address rdm) public {
        vm.assume(rdm != curator);
        address newSendAssetsGate = makeAddr("newSendAssetsGate");

        // Nobody can set directly
        vm.expectRevert(ErrorsLib.DataNotTimelocked.selector);
        vm.prank(rdm);
        vault.setSendAssetsGate(newSendAssetsGate);
        vm.expectRevert(ErrorsLib.DataNotTimelocked.selector);
        vm.prank(curator);
        vault.setSendAssetsGate(newSendAssetsGate);

        // Normal path
        vm.prank(curator);
        vault.submit(abi.encodeCall(IVaultV2.setSendAssetsGate, (newSendAssetsGate)));
        vm.expectEmit();
        emit EventsLib.SetSendAssetsGate(newSendAssetsGate);
        vault.setSendAssetsGate(newSendAssetsGate);
        assertEq(vault.sendAssetsGate(), newSendAssetsGate);
    }

    function testSetRegistryTimelocked(address rdm) public {
        vm.assume(rdm != curator);
        address newRegistry = makeAddr("newRegistry");

        vm.expectRevert(ErrorsLib.DataNotTimelocked.selector);
        vm.prank(rdm);
        vault.setAdapterRegistry(newRegistry);
    }

    function testSetRegistry(bool isInRegistry) public {
        address newAdapter = makeAddr("newAdapter");
        address newRegistry = makeAddr("newRegistry");

        vm.prank(curator);
        vault.submit(abi.encodeCall(IVaultV2.addAdapter, (newAdapter)));
        vault.addAdapter(newAdapter);

        vm.mockCall(
            address(newRegistry),
            abi.encodeWithSelector(IAdapterRegistry.isInRegistry.selector, newAdapter),
            abi.encode(isInRegistry)
        );

        vm.prank(curator);
        vault.submit(abi.encodeCall(IVaultV2.setAdapterRegistry, (newRegistry)));
        if (isInRegistry) {
            vm.expectEmit();
            emit EventsLib.SetAdapterRegistry(newRegistry);
        } else {
            vm.expectRevert(ErrorsLib.NotInAdapterRegistry.selector);
        }
        vault.setAdapterRegistry(newRegistry);
        if (isInRegistry) assertEq(vault.adapterRegistry(), newRegistry);
    }

    function testAbdicate(address rdm, bytes4 selector) public {
        vm.assume(rdm != curator);
        vm.assume(selector != bytes4(0));

        // Nobody can abdicate directly
        vm.expectRevert(ErrorsLib.DataNotTimelocked.selector);
        vm.prank(rdm);
        vault.abdicate(selector);
        vm.expectRevert(ErrorsLib.DataNotTimelocked.selector);
        vm.prank(curator);
        vault.abdicate(selector);

        // Normal path
        vm.prank(curator);
        vault.submit(abi.encodeCall(IVaultV2.abdicate, (selector)));
        vm.expectEmit();
        emit EventsLib.Abdicate(selector);
        vault.abdicate(selector);
        assertTrue(vault.abdicated(selector));
    }

    function testAbdicateSetIsAllocator(address account, bool isAllocator) public {
        _abdicateEffect(abi.encodeCall(IVaultV2.setIsAllocator, (account, isAllocator)));

        vm.expectRevert(ErrorsLib.Abdicated.selector);
        vault.setIsAllocator(account, isAllocator);
    }

    function testAbdicateSetReceiveSharesGate(address newReceiveSharesGate) public {
        _abdicateEffect(abi.encodeCall(IVaultV2.setReceiveSharesGate, (newReceiveSharesGate)));

        vm.expectRevert(ErrorsLib.Abdicated.selector);
        vault.setReceiveSharesGate(newReceiveSharesGate);
    }

    function testAbdicateSetSendSharesGate(address newSendSharesGate) public {
        _abdicateEffect(abi.encodeCall(IVaultV2.setSendSharesGate, (newSendSharesGate)));

        vm.expectRevert(ErrorsLib.Abdicated.selector);
        vault.setSendSharesGate(newSendSharesGate);
    }

    function testAbdicateSetReceiveAssetsGate(address newReceiveAssetsGate) public {
        _abdicateEffect(abi.encodeCall(IVaultV2.setReceiveAssetsGate, (newReceiveAssetsGate)));

        vm.expectRevert(ErrorsLib.Abdicated.selector);
        vault.setReceiveAssetsGate(newReceiveAssetsGate);
    }

    function testAbdicateSetSendAssetsGate(address newSendAssetsGate) public {
        _abdicateEffect(abi.encodeCall(IVaultV2.setSendAssetsGate, (newSendAssetsGate)));

        vm.expectRevert(ErrorsLib.Abdicated.selector);
        vault.setSendAssetsGate(newSendAssetsGate);
    }

    function testAbdicateSetAdapterRegistry(address newAdapterRegistry) public {
        _abdicateEffect(abi.encodeCall(IVaultV2.setAdapterRegistry, (newAdapterRegistry)));

        vm.expectRevert(ErrorsLib.Abdicated.selector);
        vault.setAdapterRegistry(newAdapterRegistry);
    }

    function testAbdicateAddAdapter(address adapter) public {
        _abdicateEffect(abi.encodeCall(IVaultV2.addAdapter, (adapter)));

        vm.expectRevert(ErrorsLib.Abdicated.selector);
        vault.addAdapter(adapter);
    }

    function testAbdicateRemoveAdapter(address adapter) public {
        _abdicateEffect(abi.encodeCall(IVaultV2.removeAdapter, (adapter)));

        vm.expectRevert(ErrorsLib.Abdicated.selector);
        vault.removeAdapter(adapter);
    }

    function testAbdicateIncreaseTimelock(bytes4 selector, uint256 newDuration) public {
        // Prepare timelock increase
        vm.prank(curator);
        vault.submit(abi.encodeCall(IVaultV2.increaseTimelock, (IVaultV2.increaseTimelock.selector, 2 weeks)));
        vault.increaseTimelock(IVaultV2.increaseTimelock.selector, 2 weeks);
        assertEq(vault.timelock(IVaultV2.increaseTimelock.selector), 2 weeks);

        vm.prank(curator);
        vault.submit(abi.encodeCall(IVaultV2.abdicate, (IVaultV2.increaseTimelock.selector)));
        vault.abdicate(IVaultV2.increaseTimelock.selector);
        assertTrue(vault.abdicated(IVaultV2.increaseTimelock.selector));

        // Submit still works
        vm.prank(curator);
        vault.submit(abi.encodeCall(IVaultV2.increaseTimelock, (selector, newDuration)));
        assertEq(
            vault.executableAt(abi.encodeCall(IVaultV2.increaseTimelock, (selector, newDuration))),
            block.timestamp + 2 weeks
        );

        // Timelock decrease still work
        vm.prank(curator);
        vault.submit(abi.encodeCall(IVaultV2.decreaseTimelock, (IVaultV2.increaseTimelock.selector, 0)));
        skip(2 weeks);
        vault.decreaseTimelock(IVaultV2.increaseTimelock.selector, 0);
        assertEq(vault.timelock(IVaultV2.increaseTimelock.selector), 0);

        vm.expectRevert(ErrorsLib.Abdicated.selector);
        vault.increaseTimelock(selector, newDuration);
    }

    function testAbdicateAbdicate(bytes4 selector) public {
        vm.prank(curator);
        vault.submit(abi.encodeCall(IVaultV2.abdicate, (IVaultV2.abdicate.selector)));
        vault.abdicate(IVaultV2.abdicate.selector);
        assertTrue(vault.abdicated(IVaultV2.abdicate.selector));

        // Timelock changes still work
        vm.prank(curator);
        vault.submit(abi.encodeCall(IVaultV2.increaseTimelock, (IVaultV2.abdicate.selector, 2 weeks)));
        vault.increaseTimelock(IVaultV2.abdicate.selector, 2 weeks);
        assertEq(vault.timelock(IVaultV2.abdicate.selector), 2 weeks);

        // Submit still works
        vm.prank(curator);
        vault.submit(abi.encodeCall(IVaultV2.abdicate, (selector)));
        assertEq(vault.executableAt(abi.encodeCall(IVaultV2.abdicate, (selector))), block.timestamp + 2 weeks);

        vm.prank(curator);
        vault.submit(abi.encodeCall(IVaultV2.decreaseTimelock, (IVaultV2.abdicate.selector, 0)));
        skip(2 weeks);
        vault.decreaseTimelock(IVaultV2.abdicate.selector, 0);
        assertEq(vault.timelock(IVaultV2.abdicate.selector), 0);

        vm.expectRevert(ErrorsLib.Abdicated.selector);
        vault.abdicate(selector);
    }

    function testAbdicateSetPerformanceFee(uint256 newPerformanceFee) public {
        _abdicateEffect(abi.encodeCall(IVaultV2.setPerformanceFee, (newPerformanceFee)));

        vm.expectRevert(ErrorsLib.Abdicated.selector);
        vault.setPerformanceFee(newPerformanceFee);
    }

    function testAbdicateSetManagementFee(uint256 newManagementFee) public {
        _abdicateEffect(abi.encodeCall(IVaultV2.setManagementFee, (newManagementFee)));

        vm.expectRevert(ErrorsLib.Abdicated.selector);
        vault.setManagementFee(newManagementFee);
    }

    function testAbdicateSetPerformanceFeeRecipient(address newPerformanceFeeRecipient) public {
        _abdicateEffect(abi.encodeCall(IVaultV2.setPerformanceFeeRecipient, (newPerformanceFeeRecipient)));

        vm.expectRevert(ErrorsLib.Abdicated.selector);
        vault.setPerformanceFeeRecipient(newPerformanceFeeRecipient);
    }

    function testAbdicateSetManagementFeeRecipient(address newManagementFeeRecipient) public {
        _abdicateEffect(abi.encodeCall(IVaultV2.setManagementFeeRecipient, (newManagementFeeRecipient)));

        vm.expectRevert(ErrorsLib.Abdicated.selector);
        vault.setManagementFeeRecipient(newManagementFeeRecipient);
    }

    function testAbdicateIncreaseAbsoluteCap(bytes memory idData, uint256 newAbsoluteCap) public {
        _abdicateEffect(abi.encodeCall(IVaultV2.increaseAbsoluteCap, (idData, newAbsoluteCap)));

        vm.expectRevert(ErrorsLib.Abdicated.selector);
        vault.increaseAbsoluteCap(idData, newAbsoluteCap);
    }

    function testAbdicateIncreaseRelativeCap(bytes memory idData, uint256 newRelativeCap) public {
        _abdicateEffect(abi.encodeCall(IVaultV2.increaseRelativeCap, (idData, newRelativeCap)));

        vm.expectRevert(ErrorsLib.Abdicated.selector);
        vault.increaseRelativeCap(idData, newRelativeCap);
    }

    function testAbdicateSetForceDeallocatePenalty(address adapter, uint256 newForceDeallocatePenalty) public {
        _abdicateEffect(abi.encodeCall(IVaultV2.setForceDeallocatePenalty, (adapter, newForceDeallocatePenalty)));

        vm.expectRevert(ErrorsLib.Abdicated.selector);
        vault.setForceDeallocatePenalty(adapter, newForceDeallocatePenalty);
    }

    function _abdicateEffect(bytes memory data) internal {
        bytes4 selector = bytes4(data);

        vm.prank(curator);
        vault.submit(abi.encodeCall(IVaultV2.abdicate, (selector)));
        vault.abdicate(selector);
        assertTrue(vault.abdicated(selector));

        // Timelock increase still work
        vm.prank(curator);
        vault.submit(abi.encodeCall(IVaultV2.increaseTimelock, (selector, 2 weeks)));
        vault.increaseTimelock(selector, 2 weeks);
        assertEq(vault.timelock(selector), 2 weeks);

        // Submit still works
        vm.prank(curator);
        vault.submit(data);
        assertEq(vault.executableAt(data), block.timestamp + 2 weeks);

        // Timelock decrease still work
        vm.prank(curator);
        vault.submit(abi.encodeCall(IVaultV2.decreaseTimelock, (selector, 0)));
        skip(2 weeks);
        vault.decreaseTimelock(selector, 0);
        assertEq(vault.timelock(selector), 0);
    }

    /* ALLOCATOR SETTERS */

    function testsetLiquidityAdapterAndData(address rdm, address liquidityAdapter, bytes memory liquidityData) public {
        vm.assume(rdm != allocator);
        vm.assume(liquidityAdapter != address(0));
        vm.assume(rdm != allocator);

        // Access control
        vm.expectRevert(ErrorsLib.Unauthorized.selector);
        vm.prank(rdm);
        vault.setLiquidityAdapterAndData(liquidityAdapter, liquidityData);

        // Normal path
        vm.prank(curator);
        vault.submit(abi.encodeCall(IVaultV2.addAdapter, (liquidityAdapter)));
        vault.addAdapter(liquidityAdapter);
        vm.prank(allocator);
        vm.expectEmit();
        emit EventsLib.SetLiquidityAdapterAndData(allocator, liquidityAdapter, liquidityData);
        vault.setLiquidityAdapterAndData(liquidityAdapter, liquidityData);
        assertEq(vault.liquidityAdapter(), liquidityAdapter);
        assertEq(vault.liquidityData(), liquidityData);
    }

    /* ABDICATION */

    function testSetAllocatorAbdicated(address rdm) public {
        testAbdicate(IVaultV2.setIsAllocator.selector);

        // No pending data.
        vm.expectRevert(ErrorsLib.Abdicated.selector);
        vm.prank(rdm);
        vault.setIsAllocator(address(1), true);

        // Pending data.
        vm.prank(curator);
        vault.submit(abi.encodeCall(IVaultV2.setIsAllocator, (address(1), true)));
        vm.prank(rdm);
        vm.expectRevert(ErrorsLib.Abdicated.selector);
        vault.setIsAllocator(address(1), true);
    }
}
