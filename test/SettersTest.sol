// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import "./BaseTest.sol";

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
        assertEq(address(vault.interestController()), address(interestController));
        assertEq(interestController.owner(), manager);
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

    /* CURATOR SETTERS */

    function testSubmit(bytes memory data, address rdm) public {
        vm.assume(rdm != curator);

        // Only curator can submit
        vm.assume(rdm != curator);
        vm.expectRevert(ErrorsLib.Unauthorized.selector);
        vm.prank(rdm);
        vault.submit(data);

        // Normal path
        vm.expectEmit();
        emit EventsLib.Submit(curator, bytes4(data), data, block.timestamp + vault.timelock(bytes4(data)));
        vm.prank(curator);
        vault.submit(data);
        assertEq(vault.validAt(data), block.timestamp + vault.timelock(bytes4(data)));

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
        uint256 snapshot = vm.snapshot();
        vm.prank(sentinel);
        vm.expectEmit();
        emit EventsLib.Revoke(sentinel, bytes4(data), data);
        vault.revoke(data);
        assertEq(vault.validAt(data), 0);

        // Curator can revoke as well
        vm.revertTo(snapshot);
        vm.prank(curator);
        vault.revoke(data);
        assertEq(vault.validAt(data), 0);
    }

    function testTimelocked(uint256 timelock) public {
        timelock = bound(timelock, 1, TIMELOCK_CAP);

        // Setup.
        vm.prank(curator);
        vault.increaseTimelock(IVaultV2.setInterestController.selector, timelock);
        assertEq(vault.timelock(IVaultV2.setInterestController.selector), timelock);
        bytes memory data = abi.encodeWithSelector(IVaultV2.setInterestController.selector, address(1));
        vm.prank(curator);
        vault.submit(data);
        assertEq(vault.validAt(data), block.timestamp + timelock);

        // Timelock didn't pass.
        vm.warp(vm.getBlockTimestamp() + timelock - 1);
        vm.expectRevert(ErrorsLib.TimelockNotExpired.selector);
        vault.setInterestController(address(1));

        // Normal path.
        vm.warp(vm.getBlockTimestamp() + 1);
        vault.setInterestController(address(1));

        // Data not timelocked.
        vm.expectRevert(ErrorsLib.DataNotTimelocked.selector);
        vault.setInterestController(address(1));
    }

    function testSetIsAllocator(address rdm) public {
        address newAllocator = makeAddr("newAllocator");

        // Nobody can set directly
        vm.expectRevert(ErrorsLib.DataNotTimelocked.selector);
        vm.prank(rdm);
        vault.setIsAllocator(newAllocator, true);

        // Normal path
        vm.prank(curator);
        vault.submit(abi.encodeWithSelector(IVaultV2.setIsAllocator.selector, newAllocator, true));
        vm.expectEmit();
        emit EventsLib.SetIsAllocator(newAllocator, true);
        vault.setIsAllocator(newAllocator, true);
        assertTrue(vault.isAllocator(newAllocator));

        // Removal
        vm.prank(curator);
        vault.submit(abi.encodeWithSelector(IVaultV2.setIsAllocator.selector, newAllocator, false));
        vm.expectEmit();
        emit EventsLib.SetIsAllocator(newAllocator, false);
        vault.setIsAllocator(newAllocator, false);
        assertFalse(vault.isAllocator(newAllocator));
    }

    function testSetInterestController(address rdm) public {
        vm.assume(rdm != curator);
        address newInterestController = address(new ManualInterestController(manager));

        // Nobody can set directly
        vm.expectRevert(ErrorsLib.DataNotTimelocked.selector);
        vm.prank(rdm);
        vault.setInterestController(newInterestController);

        // Normal path
        vm.prank(curator);
        vault.submit(abi.encodeWithSelector(IVaultV2.setInterestController.selector, newInterestController));
        vm.expectEmit();
        emit EventsLib.SetInterestController(newInterestController);
        vault.setInterestController(newInterestController);
        assertEq(address(vault.interestController()), newInterestController);
    }

    function testSetIsAdapter(address rdm) public {
        vm.assume(rdm != curator);
        address newAdapter = makeAddr("newAdapter");

        // Nobody can set directly
        vm.expectRevert(ErrorsLib.DataNotTimelocked.selector);
        vm.prank(rdm);
        vault.setIsAdapter(newAdapter, true);

        // Normal path
        vm.prank(curator);
        vault.submit(abi.encodeWithSelector(IVaultV2.setIsAdapter.selector, newAdapter, true));
        vm.expectEmit();
        emit EventsLib.SetIsAdapter(newAdapter, true);
        vault.setIsAdapter(newAdapter, true);
        assertTrue(vault.isAdapter(newAdapter));

        // Removal
        vm.prank(curator);
        vault.submit(abi.encodeWithSelector(IVaultV2.setIsAdapter.selector, newAdapter, false));
        vm.expectEmit();
        emit EventsLib.SetIsAdapter(newAdapter, false);
        vault.setIsAdapter(newAdapter, false);
        assertFalse(vault.isAdapter(newAdapter));

        // Liquidity adapter invariant
        vm.prank(curator);
        vault.submit(abi.encodeWithSelector(IVaultV2.setIsAdapter.selector, newAdapter, true));
        vault.setIsAdapter(newAdapter, true);
        vm.prank(allocator);
        vault.setLiquidityAdapter(newAdapter);
        vm.prank(curator);
        vault.submit(abi.encodeWithSelector(IVaultV2.setIsAdapter.selector, newAdapter, false));
        vm.expectRevert(ErrorsLib.LiquidityAdapterInvariantBroken.selector);
        vault.setIsAdapter(newAdapter, false);
    }

    function testIncreaseTimelock(address rdm, bytes4 selector, uint256 newTimelock) public {
        vm.assume(rdm != curator);
        vm.assume(newTimelock <= 2 weeks);
        vm.assume(newTimelock >= 0);
        vm.assume(selector != IVaultV2.decreaseTimelock.selector);

        // Access control
        vm.expectRevert(ErrorsLib.Unauthorized.selector);
        vm.prank(rdm);
        vault.increaseTimelock(selector, newTimelock);

        // Cannot increase timelock of decreaseTimelock
        vm.expectRevert(ErrorsLib.TimelockCapIsFixed.selector);
        vm.prank(curator);
        vault.increaseTimelock(IVaultV2.decreaseTimelock.selector, 3 weeks);

        // Can't go over timelock cap
        vm.expectRevert(ErrorsLib.TimelockDurationTooHigh.selector);
        vm.prank(curator);
        vault.increaseTimelock(selector, TIMELOCK_CAP + 1);

        // Normal path
        vm.expectEmit();
        emit EventsLib.IncreaseTimelock(selector, newTimelock);
        vm.prank(curator);
        vault.increaseTimelock(selector, newTimelock);
        assertEq(vault.timelock(selector), newTimelock);

        // Can't decrease timelock
        if (newTimelock > 0) {
            vm.expectRevert(ErrorsLib.TimelockNotIncreasing.selector);
            vm.prank(curator);
            vault.increaseTimelock(selector, newTimelock - 1);
        }
    }

    function testDecreaseTimelock(address rdm, bytes4 selector, uint256 oldTimelock, uint256 newTimelock) public {
        vm.assume(rdm != curator);
        vm.assume(selector != IVaultV2.decreaseTimelock.selector);
        vm.assume(oldTimelock >= newTimelock);
        vm.assume(oldTimelock <= 2 weeks);

        vm.prank(curator);
        vault.increaseTimelock(selector, oldTimelock);

        // Nobody can set directly
        vm.expectRevert(ErrorsLib.DataNotTimelocked.selector);
        vm.prank(rdm);
        vault.decreaseTimelock(selector, newTimelock);

        // Can't increase timelock with decreaseTimelock
        vm.prank(curator);
        vault.submit(abi.encodeWithSelector(IVaultV2.decreaseTimelock.selector, selector, oldTimelock + 1));
        vm.warp(vm.getBlockTimestamp() + TIMELOCK_CAP);
        vm.expectRevert(ErrorsLib.TimelockNotDecreasing.selector);
        vault.decreaseTimelock(selector, oldTimelock + 1);

        // Normal path
        vm.prank(curator);
        vault.submit(abi.encodeWithSelector(IVaultV2.decreaseTimelock.selector, selector, newTimelock));
        vm.warp(vm.getBlockTimestamp() + TIMELOCK_CAP);
        vm.expectEmit();
        emit EventsLib.DecreaseTimelock(selector, newTimelock);
        vault.decreaseTimelock(selector, newTimelock);
        assertEq(vault.timelock(selector), newTimelock);

        // Cannot decrease decreaseTimelock's timelock
        vm.prank(curator);
        vault.submit(
            abi.encodeWithSelector(IVaultV2.decreaseTimelock.selector, IVaultV2.decreaseTimelock.selector, 1 weeks)
        );
        vm.warp(vm.getBlockTimestamp() + TIMELOCK_CAP);
        vm.expectRevert(ErrorsLib.TimelockCapIsFixed.selector);
        vault.decreaseTimelock(IVaultV2.decreaseTimelock.selector, 1 weeks);
    }

    function testSetPerformanceFee(address rdm, uint256 newPerformanceFee) public {
        vm.assume(rdm != curator);
        newPerformanceFee = bound(newPerformanceFee, 1, MAX_PERFORMANCE_FEE);

        // Nobody can set directly
        vm.expectRevert(ErrorsLib.DataNotTimelocked.selector);
        vm.prank(rdm);
        vault.setPerformanceFee(newPerformanceFee);

        // No op works
        vm.prank(curator);
        vault.submit(abi.encodeWithSelector(IVaultV2.setPerformanceFee.selector, 0));
        vault.setPerformanceFee(0);

        // Can't go over fee cap
        uint256 tooHighFee = 1 ether + 1;
        vm.prank(curator);
        vault.submit(abi.encodeWithSelector(IVaultV2.setPerformanceFee.selector, tooHighFee));
        vm.expectRevert(ErrorsLib.FeeTooHigh.selector);
        vault.setPerformanceFee(tooHighFee);

        // Fee invariant
        vm.prank(curator);
        vault.submit(abi.encodeWithSelector(IVaultV2.setPerformanceFee.selector, newPerformanceFee));
        vm.expectRevert(ErrorsLib.FeeInvariantBroken.selector);
        vault.setPerformanceFee(newPerformanceFee);

        // Normal path
        vm.prank(curator);
        vault.submit(
            abi.encodeWithSelector(IVaultV2.setPerformanceFeeRecipient.selector, makeAddr("newPerformanceFeeRecipient"))
        );
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

        // No op works
        vm.prank(curator);
        vault.submit(abi.encodeWithSelector(IVaultV2.setManagementFee.selector, 0));
        vault.setManagementFee(0);

        // Can't go over fee cap
        uint256 tooHighFee = 1 ether + 1;
        vm.prank(curator);
        vault.submit(abi.encodeWithSelector(IVaultV2.setManagementFee.selector, tooHighFee));
        vm.expectRevert(ErrorsLib.FeeTooHigh.selector);
        vault.setManagementFee(tooHighFee);

        // Fee invariant
        vm.prank(curator);
        vault.submit(abi.encodeWithSelector(IVaultV2.setManagementFee.selector, newManagementFee));
        vm.expectRevert(ErrorsLib.FeeInvariantBroken.selector);
        vault.setManagementFee(newManagementFee);

        // Normal path
        vm.prank(curator);
        vault.submit(
            abi.encodeWithSelector(IVaultV2.setManagementFeeRecipient.selector, makeAddr("newManagementFeeRecipient"))
        );
        vault.setManagementFeeRecipient(makeAddr("newManagementFeeRecipient"));
        vm.expectEmit();
        emit EventsLib.SetManagementFee(newManagementFee);
        vault.setManagementFee(newManagementFee);
        assertEq(vault.managementFee(), newManagementFee);
    }

    function testSetPerformanceFeeRecipient(address rdm, address newPerformanceFeeRecipient) public {
        vm.assume(rdm != curator);
        vm.assume(newPerformanceFeeRecipient != address(0));

        // Nobody can set directly
        vm.expectRevert(ErrorsLib.DataNotTimelocked.selector);
        vm.prank(rdm);
        vault.setPerformanceFeeRecipient(newPerformanceFeeRecipient);

        // Normal path
        vm.prank(curator);
        vault.submit(abi.encodeWithSelector(IVaultV2.setPerformanceFeeRecipient.selector, newPerformanceFeeRecipient));
        vm.expectEmit();
        emit EventsLib.SetPerformanceFeeRecipient(newPerformanceFeeRecipient);
        vault.setPerformanceFeeRecipient(newPerformanceFeeRecipient);
        assertEq(vault.performanceFeeRecipient(), newPerformanceFeeRecipient);

        // Fee invariant
        uint256 newPerformanceFee = 0.05 ether;
        vm.prank(curator);
        vault.submit(abi.encodeWithSelector(IVaultV2.setPerformanceFee.selector, newPerformanceFee));
        vault.setPerformanceFee(newPerformanceFee);
        vm.prank(curator);
        vault.submit(abi.encodeWithSelector(IVaultV2.setPerformanceFeeRecipient.selector, address(0)));
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

        // Normal path
        vm.prank(curator);
        vault.submit(abi.encodeWithSelector(IVaultV2.setManagementFeeRecipient.selector, newManagementFeeRecipient));
        vm.expectEmit();
        emit EventsLib.SetManagementFeeRecipient(newManagementFeeRecipient);
        vault.setManagementFeeRecipient(newManagementFeeRecipient);
        assertEq(vault.managementFeeRecipient(), newManagementFeeRecipient);

        // Fee invariant
        uint256 newManagementFee = 0.01 ether / uint256(365.25 days);
        vm.prank(curator);
        vault.submit(abi.encodeWithSelector(IVaultV2.setManagementFee.selector, newManagementFee));
        vault.setManagementFee(newManagementFee);
        vm.prank(curator);
        vault.submit(abi.encodeWithSelector(IVaultV2.setManagementFeeRecipient.selector, address(0)));
        vm.expectRevert(ErrorsLib.FeeInvariantBroken.selector);
        vault.setManagementFeeRecipient(address(0));
    }

    function testIncreaseAbsoluteCap(address rdm, bytes memory idData, uint256 newAbsoluteCap) public {
        vm.assume(rdm != curator);
        vm.assume(newAbsoluteCap >= 0);
        bytes32 id = keccak256(idData);

        // Nobody can set directly
        vm.expectRevert(ErrorsLib.DataNotTimelocked.selector);
        vm.prank(rdm);
        vault.increaseAbsoluteCap(idData, newAbsoluteCap);

        // Normal path
        vm.prank(curator);
        vault.submit(abi.encodeWithSelector(IVaultV2.increaseAbsoluteCap.selector, idData, newAbsoluteCap));
        vm.expectEmit();
        emit EventsLib.IncreaseAbsoluteCap(id, idData, newAbsoluteCap);
        vault.increaseAbsoluteCap(idData, newAbsoluteCap);
        assertEq(vault.absoluteCap(id), newAbsoluteCap);

        // Can't decrease absolute cap
        if (newAbsoluteCap > 0) {
            vm.prank(curator);
            vault.submit(abi.encodeWithSelector(IVaultV2.increaseAbsoluteCap.selector, idData, newAbsoluteCap - 1));
            vm.expectRevert(ErrorsLib.AbsoluteCapNotIncreasing.selector);
            vault.increaseAbsoluteCap(idData, newAbsoluteCap - 1);
        }
    }

    function testDecreaseAbsoluteCap(address rdm, bytes memory idData, uint256 oldAbsoluteCap, uint256 newAbsoluteCap)
        public
    {
        vm.assume(rdm != curator);
        vm.assume(newAbsoluteCap >= 0);
        vm.assume(oldAbsoluteCap >= newAbsoluteCap);
        vm.assume(oldAbsoluteCap < type(uint256).max);
        bytes32 id = keccak256(idData);

        vm.prank(curator);
        vault.submit(abi.encodeWithSelector(IVaultV2.increaseAbsoluteCap.selector, idData, oldAbsoluteCap));
        vault.increaseAbsoluteCap(idData, oldAbsoluteCap);

        // Access control
        vm.expectRevert(ErrorsLib.Unauthorized.selector);
        vm.prank(rdm);
        vault.decreaseAbsoluteCap(id, newAbsoluteCap);

        // Can't increase absolute cap
        vm.expectRevert(ErrorsLib.AbsoluteCapNotDecreasing.selector);
        vm.prank(curator);
        vault.decreaseAbsoluteCap(id, oldAbsoluteCap + 1);

        // Normal path
        vm.expectEmit();
        emit EventsLib.DecreaseAbsoluteCap(id, newAbsoluteCap);
        vm.prank(curator);
        vault.decreaseAbsoluteCap(id, newAbsoluteCap);
        assertEq(vault.absoluteCap(id), newAbsoluteCap);
    }

    function testIncreaseRelativeCap(address rdm, bytes32 id, uint256 newRelativeCap) public {
        vm.assume(newRelativeCap >= 0);
        vm.assume(newRelativeCap <= WAD);

        // Nobody can set directly
        vm.expectRevert(ErrorsLib.DataNotTimelocked.selector);
        vm.prank(rdm);
        vault.increaseRelativeCap(id, newRelativeCap);

        // Can't increase relative cap above 1
        vm.prank(curator);
        vault.submit(abi.encodeWithSelector(IVaultV2.increaseRelativeCap.selector, id, WAD + 1));
        vm.expectRevert(ErrorsLib.RelativeCapAboveOne.selector);
        vault.increaseRelativeCap(id, WAD + 1);

        // Normal path
        vm.prank(curator);
        vault.submit(abi.encodeWithSelector(IVaultV2.increaseRelativeCap.selector, id, newRelativeCap));
        vm.expectEmit();
        emit EventsLib.IncreaseRelativeCap(id, newRelativeCap);
        vault.increaseRelativeCap(id, newRelativeCap);
        assertEq(vault.relativeCap(id), newRelativeCap);
        assertEq(vault.idsWithRelativeCap(0), id);

        // Can't decrease relative cap
        if (newRelativeCap > 0) {
            vm.prank(curator);
            vault.submit(abi.encodeWithSelector(IVaultV2.increaseRelativeCap.selector, id, newRelativeCap - 1));
            vm.expectRevert(ErrorsLib.RelativeCapNotIncreasing.selector);
            vault.increaseRelativeCap(id, newRelativeCap - 1);
        }
    }

    function testDecreaseRelativeCap(address rdm, bytes32 id, uint256 oldRelativeCap, uint256 newRelativeCap) public {
        vm.assume(newRelativeCap >= 0);
        vm.assume(oldRelativeCap >= newRelativeCap);
        vm.assume(oldRelativeCap <= WAD);

        vm.prank(curator);
        vault.submit(abi.encodeWithSelector(IVaultV2.increaseRelativeCap.selector, id, oldRelativeCap));
        vault.increaseRelativeCap(id, oldRelativeCap);

        // Access control
        vm.expectRevert(ErrorsLib.DataNotTimelocked.selector);
        vm.prank(rdm);
        vault.decreaseRelativeCap(id, newRelativeCap);

        // Normal path
        vm.prank(curator);
        vault.submit(abi.encodeWithSelector(IVaultV2.decreaseRelativeCap.selector, id, newRelativeCap));
        vm.expectEmit();
        emit EventsLib.DecreaseRelativeCap(id, newRelativeCap);
        vault.decreaseRelativeCap(id, newRelativeCap);
        assertEq(vault.relativeCap(id), newRelativeCap);

        // Can't increase relative cap
        vm.prank(curator);
        vault.submit(abi.encodeWithSelector(IVaultV2.decreaseRelativeCap.selector, id, newRelativeCap + 1));
        vm.expectRevert(ErrorsLib.RelativeCapNotDecreasing.selector);
        vault.decreaseRelativeCap(id, newRelativeCap + 1);

        // The relative cap decreased to 0.
        vm.prank(curator);
        vault.submit(abi.encodeWithSelector(IVaultV2.decreaseRelativeCap.selector, id, 0));
        vault.decreaseRelativeCap(id, 0);
        vm.expectRevert();
        vault.idsWithRelativeCap(0);

        // The relative cap exceeded.
        id = keccak256("id");
        vm.prank(curator);
        vault.submit(abi.encodeWithSelector(IVaultV2.increaseRelativeCap.selector, id, oldRelativeCap));
        vault.increaseRelativeCap(id, oldRelativeCap);
        vm.prank(curator);
        vault.submit(abi.encodeWithSelector(IVaultV2.increaseAbsoluteCap.selector, "id", oldRelativeCap));
        vault.increaseAbsoluteCap("id", oldRelativeCap);
        vault.deposit(1 ether, address(this));
        address adapter = address(new BasicAdapter());
        vm.prank(curator);
        vault.submit(abi.encodeWithSelector(IVaultV2.setIsAdapter.selector, adapter, true));
        vault.setIsAdapter(adapter, true);
        vm.prank(allocator);
        vault.reallocateFromIdle(adapter, hex"", oldRelativeCap);
        assertEq(vault.allocation(id), oldRelativeCap);
        vm.prank(curator);
        vault.submit(abi.encodeWithSelector(IVaultV2.decreaseRelativeCap.selector, id, newRelativeCap));
        vm.expectRevert(ErrorsLib.RelativeCapExceeded.selector);
        vault.decreaseRelativeCap(id, newRelativeCap);
    }

    function testSetForceReallocateToIdlePenalty(address rdm, uint256 newForceReallocateToIdlePenalty) public {
        vm.assume(rdm != curator);
        newForceReallocateToIdlePenalty =
            bound(newForceReallocateToIdlePenalty, 0, MAX_FORCE_REALLOCATE_TO_IDLE_PENALTY);

        // Nobody can set directly
        vm.expectRevert(ErrorsLib.DataNotTimelocked.selector);
        vault.setForceReallocateToIdlePenalty(newForceReallocateToIdlePenalty);

        // Normal path
        vm.prank(curator);
        vault.submit(
            abi.encodeWithSelector(IVaultV2.setForceReallocateToIdlePenalty.selector, newForceReallocateToIdlePenalty)
        );
        vm.expectEmit();
        emit EventsLib.SetForceReallocateToIdlePenalty(newForceReallocateToIdlePenalty);
        vault.setForceReallocateToIdlePenalty(newForceReallocateToIdlePenalty);
        assertEq(vault.forceReallocateToIdlePenalty(), newForceReallocateToIdlePenalty);

        // Can't set fee above cap
        uint256 tooHighPenalty = MAX_FORCE_REALLOCATE_TO_IDLE_PENALTY + 1;
        vm.prank(curator);
        vault.submit(abi.encodeWithSelector(IVaultV2.setForceReallocateToIdlePenalty.selector, tooHighPenalty));
        vm.expectRevert(ErrorsLib.PenaltyTooHigh.selector);
        vault.setForceReallocateToIdlePenalty(tooHighPenalty);
    }

    /* ALLOCATOR SETTERS */

    function testSetLiquidityAdapter(address rdm, address liquidityAdapter) public {
        vm.assume(rdm != allocator);
        vm.assume(liquidityAdapter != address(0));
        vm.assume(rdm != allocator);
        vm.prank(allocator);
        vm.expectRevert(abi.encodeWithSelector(ErrorsLib.LiquidityAdapterInvariantBroken.selector));
        vault.setLiquidityAdapter(liquidityAdapter);

        // Access control
        vm.expectRevert(ErrorsLib.Unauthorized.selector);
        vm.prank(rdm);
        vault.setLiquidityAdapter(liquidityAdapter);

        // Normal path
        vm.prank(curator);
        vault.submit(abi.encodeWithSelector(IVaultV2.setIsAdapter.selector, liquidityAdapter, true));
        vault.setIsAdapter(liquidityAdapter, true);
        vm.prank(allocator);
        vm.expectEmit();
        emit EventsLib.SetLiquidityAdapter(allocator, liquidityAdapter);
        vault.setLiquidityAdapter(liquidityAdapter);
        assertEq(vault.liquidityAdapter(), liquidityAdapter);

        // Liquidity adapter invariant
        vm.prank(curator);
        vault.submit(abi.encodeWithSelector(IVaultV2.setIsAdapter.selector, liquidityAdapter, false));
        vm.expectRevert(abi.encodeWithSelector(ErrorsLib.LiquidityAdapterInvariantBroken.selector));
        vault.setIsAdapter(liquidityAdapter, false);
    }

    function testSetLiquidityData(address rdm) public {
        vm.assume(rdm != allocator);
        bytes memory newData = abi.encode("newData");

        // Access control
        vm.expectRevert(ErrorsLib.Unauthorized.selector);
        vm.prank(rdm);
        vault.setLiquidityData(newData);

        // Normal path
        vm.prank(allocator);
        vm.expectEmit();
        emit EventsLib.SetLiquidityData(allocator, newData);
        vault.setLiquidityData(newData);
        assertEq(vault.liquidityData(), newData);
    }
}

contract BasicAdapter {
    function allocateIn(bytes memory, uint256) external pure returns (bytes32[] memory) {
        bytes32[] memory ids = new bytes32[](1);
        ids[0] = keccak256("id");
        return ids;
    }
}
