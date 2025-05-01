// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import "./BaseTest.sol";

contract SettersTest is BaseTest {
    function testConstructor() public view {
        assertEq(vault.owner(), owner);
        assertEq(address(vault.asset()), address(underlyingToken));
        assertEq(address(vault.curator()), curator);
        assertTrue(vault.isAllocator(address(allocator)));
        assertEq(address(vault.irm()), address(irm));
        assertEq(irm.owner(), manager);
    }

    function testSetOwner(address rdm) public {
        vm.assume(rdm != owner);
        address newOwner = makeAddr("newOwner");

        // Only owner can set
        vm.expectRevert(ErrorsLib.Unauthorized.selector);
        vm.prank(rdm);
        vault.setOwner(newOwner);

        vm.prank(owner);
        vm.expectEmit();
        emit EventsLib.SetOwner(newOwner);
        vault.setOwner(newOwner);

        assertEq(vault.owner(), newOwner);
    }

    function testSetCurator(address rdm) public {
        vm.assume(rdm != owner);
        address newCurator = makeAddr("newCurator");

        // Only owner can set
        vm.expectRevert(ErrorsLib.Unauthorized.selector);
        vm.prank(rdm);
        vault.setCurator(newCurator);

        vm.prank(owner);
        vm.expectEmit();
        emit EventsLib.SetCurator(newCurator);
        vault.setCurator(newCurator);

        assertEq(vault.curator(), newCurator);
    }

    function testSetIsSentinel(address rdm, bool newIsSentinel) public {
        vm.assume(rdm != owner);

        // Only owner can set
        vm.expectRevert(ErrorsLib.Unauthorized.selector);
        vm.prank(rdm);
        vault.setIsSentinel(rdm, newIsSentinel);

        vm.prank(owner);
        vm.expectEmit();
        emit EventsLib.SetIsSentinel(rdm, newIsSentinel);
        vault.setIsSentinel(rdm, newIsSentinel);

        assertEq(vault.isSentinel(rdm), newIsSentinel);
    }

    function testSetIRM(address rdm) public {
        vm.assume(rdm != curator);
        address newIRM = address(new IRM(manager));

        // Nobody can set directly
        vm.expectRevert(ErrorsLib.DataNotTimelocked.selector);
        vm.prank(rdm);
        vault.setIRM(newIRM);

        // Only curator can submit
        vm.expectRevert(ErrorsLib.Unauthorized.selector);
        vm.prank(rdm);
        vault.submit(abi.encodeWithSelector(IVaultV2.setIRM.selector, newIRM));

        vm.prank(curator);
        vm.expectEmit();
        emit EventsLib.Submit(curator, abi.encodeWithSelector(IVaultV2.setIRM.selector, newIRM), block.timestamp);
        vault.submit(abi.encodeWithSelector(IVaultV2.setIRM.selector, newIRM));

        vm.expectEmit();
        emit EventsLib.SetIRM(newIRM);
        vault.setIRM(newIRM);

        assertEq(address(vault.irm()), newIRM);
    }

    function testSetIsAllocator(address rdm) public {
        vm.assume(rdm != curator);
        address newAllocator = makeAddr("newAllocator");

        // Nobody can set directly
        vm.expectRevert(ErrorsLib.DataNotTimelocked.selector);
        vm.prank(rdm);
        vault.setIsAllocator(newAllocator, true);

        // Only curator can submit
        vm.expectRevert(ErrorsLib.Unauthorized.selector);
        vm.prank(rdm);
        vault.submit(abi.encodeWithSelector(IVaultV2.setIsAllocator.selector, newAllocator, true));

        vm.prank(curator);
        vm.expectEmit();
        emit EventsLib.Submit(
            curator, abi.encodeWithSelector(IVaultV2.setIsAllocator.selector, newAllocator, true), block.timestamp
        );
        vault.submit(abi.encodeWithSelector(IVaultV2.setIsAllocator.selector, newAllocator, true));

        vm.expectEmit();
        emit EventsLib.SetIsAllocator(newAllocator, true);
        vault.setIsAllocator(newAllocator, true);

        assertTrue(vault.isAllocator(newAllocator));

        // Curator can remove an allocator
        vm.prank(curator);
        vault.submit(abi.encodeWithSelector(IVaultV2.setIsAllocator.selector, newAllocator, false));
        vault.setIsAllocator(newAllocator, false);

        assertFalse(vault.isAllocator(newAllocator));
    }

    function testSetIsAdapter(address rdm) public {
        vm.assume(rdm != curator);
        address newAdapter = makeAddr("newAdapter");

        // Nobody can set directly
        vm.expectRevert(ErrorsLib.DataNotTimelocked.selector);
        vm.prank(rdm);
        vault.setIsAdapter(newAdapter, true);

        // Only curator can submit
        vm.expectRevert(ErrorsLib.Unauthorized.selector);
        vm.prank(rdm);
        vault.submit(abi.encodeWithSelector(IVaultV2.setIsAdapter.selector, newAdapter, true));

        vm.prank(curator);
        vault.submit(abi.encodeWithSelector(IVaultV2.setIsAdapter.selector, newAdapter, true));
        vault.setIsAdapter(newAdapter, true);

        assertTrue(vault.isAdapter(newAdapter));

        // Curator can remove an adapter
        vm.prank(curator);
        vault.submit(abi.encodeWithSelector(IVaultV2.setIsAdapter.selector, newAdapter, false));
        vault.setIsAdapter(newAdapter, false);

        assertFalse(vault.isAdapter(newAdapter));
    }

    function testSetPerformanceFee(address rdm, uint256 newPerformanceFee) public {
        vm.assume(rdm != curator);
        newPerformanceFee = bound(newPerformanceFee, 0, MAX_PERFORMANCE_FEE);

        // Nobody can set directly
        vm.expectRevert(ErrorsLib.DataNotTimelocked.selector);
        vm.prank(rdm);
        vault.setPerformanceFee(newPerformanceFee);

        // Only curator can submit
        vm.expectRevert(ErrorsLib.Unauthorized.selector);
        vm.prank(rdm);
        vault.submit(abi.encodeWithSelector(IVaultV2.setPerformanceFee.selector, newPerformanceFee));

        uint256 tooHighFee = 1 ether + 1;
        vm.prank(curator);
        vault.submit(abi.encodeWithSelector(IVaultV2.setPerformanceFee.selector, tooHighFee));

        vm.expectRevert(ErrorsLib.FeeTooHigh.selector);
        vault.setPerformanceFee(tooHighFee);

        vm.prank(curator);
        vm.expectEmit();
        emit EventsLib.Submit(
            curator, abi.encodeWithSelector(IVaultV2.setPerformanceFee.selector, newPerformanceFee), block.timestamp
        );
        vault.submit(abi.encodeWithSelector(IVaultV2.setPerformanceFee.selector, newPerformanceFee));

        assertEq(
            vault.validAt(abi.encodeWithSelector(IVaultV2.setPerformanceFee.selector, newPerformanceFee)),
            block.timestamp
        );

        vm.expectRevert(ErrorsLib.FeeInvariantBroken.selector);
        vault.setPerformanceFee(newPerformanceFee);

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

    function testSetPerformanceFeeRecipient(address rdm, address newPerformanceFeeRecipient) public {
        vm.assume(rdm != curator);
        vm.assume(newPerformanceFeeRecipient != address(0));

        // Nobody can set directly
        vm.expectRevert(ErrorsLib.DataNotTimelocked.selector);
        vm.prank(rdm);
        vault.setPerformanceFeeRecipient(newPerformanceFeeRecipient);

        // Only curator can submit
        vm.expectRevert(ErrorsLib.Unauthorized.selector);
        vm.prank(rdm);
        vault.submit(abi.encodeWithSelector(IVaultV2.setPerformanceFeeRecipient.selector, newPerformanceFeeRecipient));

        vm.prank(curator);
        vm.expectEmit();
        emit EventsLib.Submit(
            curator,
            abi.encodeWithSelector(IVaultV2.setPerformanceFeeRecipient.selector, newPerformanceFeeRecipient),
            block.timestamp
        );
        vault.submit(abi.encodeWithSelector(IVaultV2.setPerformanceFeeRecipient.selector, newPerformanceFeeRecipient));
        vm.expectEmit();
        emit EventsLib.SetPerformanceFeeRecipient(newPerformanceFeeRecipient);
        vault.setPerformanceFeeRecipient(newPerformanceFeeRecipient);

        assertEq(vault.performanceFeeRecipient(), newPerformanceFeeRecipient);

        uint256 newPerformanceFee = 0.05 ether;
        vm.prank(curator);
        vault.submit(abi.encodeWithSelector(IVaultV2.setPerformanceFee.selector, newPerformanceFee));
        vault.setPerformanceFee(newPerformanceFee);

        vm.prank(curator);
        vault.submit(abi.encodeWithSelector(IVaultV2.setPerformanceFeeRecipient.selector, address(0)));
        vm.expectRevert(ErrorsLib.FeeInvariantBroken.selector);
        vault.setPerformanceFeeRecipient(address(0));
    }

    function testSetManagementFee(address rdm, uint256 newManagementFee) public {
        vm.assume(rdm != curator);
        newManagementFee = bound(newManagementFee, 0, MAX_MANAGEMENT_FEE);

        // Nobody can set directly
        vm.expectRevert(ErrorsLib.DataNotTimelocked.selector);
        vm.prank(rdm);
        vault.setManagementFee(newManagementFee);

        // Only curator can submit
        vm.expectRevert(ErrorsLib.Unauthorized.selector);
        vm.prank(rdm);
        vault.submit(abi.encodeWithSelector(IVaultV2.setManagementFee.selector, newManagementFee));

        uint256 tooHighFee = 1 ether + 1;
        vm.prank(curator);
        vm.expectEmit();
        emit EventsLib.Submit(
            curator, abi.encodeWithSelector(IVaultV2.setManagementFee.selector, tooHighFee), block.timestamp
        );
        vault.submit(abi.encodeWithSelector(IVaultV2.setManagementFee.selector, tooHighFee));
        vm.expectRevert(ErrorsLib.FeeTooHigh.selector);
        vault.setManagementFee(tooHighFee);

        vm.prank(curator);
        vault.submit(abi.encodeWithSelector(IVaultV2.setManagementFee.selector, newManagementFee));

        assertEq(
            vault.validAt(abi.encodeWithSelector(IVaultV2.setManagementFee.selector, newManagementFee)), block.timestamp
        );

        vm.expectRevert(ErrorsLib.FeeInvariantBroken.selector);
        vault.setManagementFee(newManagementFee);

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

    function testSetManagementFeeRecipient(address rdm, address newManagementFeeRecipient) public {
        vm.assume(rdm != curator);
        vm.assume(newManagementFeeRecipient != address(0));

        // Nobody can set directly
        vm.expectRevert(ErrorsLib.DataNotTimelocked.selector);
        vm.prank(rdm);
        vault.setManagementFeeRecipient(newManagementFeeRecipient);

        // Only curator can submit
        vm.expectRevert(ErrorsLib.Unauthorized.selector);
        vm.prank(rdm);
        vault.submit(abi.encodeWithSelector(IVaultV2.setManagementFeeRecipient.selector, newManagementFeeRecipient));

        vm.prank(curator);
        vm.expectEmit();
        emit EventsLib.Submit(
            curator,
            abi.encodeWithSelector(IVaultV2.setManagementFeeRecipient.selector, newManagementFeeRecipient),
            block.timestamp
        );
        vault.submit(abi.encodeWithSelector(IVaultV2.setManagementFeeRecipient.selector, newManagementFeeRecipient));
        vm.expectEmit();
        emit EventsLib.SetManagementFeeRecipient(newManagementFeeRecipient);
        vault.setManagementFeeRecipient(newManagementFeeRecipient);

        assertEq(vault.managementFeeRecipient(), newManagementFeeRecipient);

        uint256 newManagementFee = 0.01 ether / uint256(365.25 days);
        vm.prank(curator);
        vault.submit(abi.encodeWithSelector(IVaultV2.setManagementFee.selector, newManagementFee));
        vault.setManagementFee(newManagementFee);

        vm.prank(curator);
        vault.submit(abi.encodeWithSelector(IVaultV2.setManagementFeeRecipient.selector, address(0)));
        vm.expectRevert(ErrorsLib.FeeInvariantBroken.selector);
        vault.setManagementFeeRecipient(address(0));
    }

    function testSetForceReallocateToIdleFee(address rdm, uint256 newForceReallocateToIdleFee) public {
        vm.assume(rdm != curator);
        newForceReallocateToIdleFee = bound(newForceReallocateToIdleFee, 0, MAX_FORCE_REALLOCATE_TO_IDLE_FEE);

        // Nobody can set directly
        vm.expectRevert(ErrorsLib.DataNotTimelocked.selector);
        vault.setForceReallocateToIdleFee(newForceReallocateToIdleFee);

        // Only curator can submit
        vm.expectRevert(ErrorsLib.Unauthorized.selector);
        vm.prank(rdm);
        vault.submit(abi.encodeWithSelector(IVaultV2.setForceReallocateToIdleFee.selector, newForceReallocateToIdleFee));

        vm.prank(curator);
        vm.expectEmit();
        emit EventsLib.Submit(
            curator,
            abi.encodeWithSelector(IVaultV2.setForceReallocateToIdleFee.selector, newForceReallocateToIdleFee),
            block.timestamp
        );
        vault.submit(abi.encodeWithSelector(IVaultV2.setForceReallocateToIdleFee.selector, newForceReallocateToIdleFee));
        vm.expectEmit();
        emit EventsLib.SetForceReallocateToIdleFee(newForceReallocateToIdleFee);
        vault.setForceReallocateToIdleFee(newForceReallocateToIdleFee);

        assertEq(vault.forceReallocateToIdleFee(), newForceReallocateToIdleFee);

        uint256 tooHighFee = MAX_FORCE_REALLOCATE_TO_IDLE_FEE + 1;
        vm.prank(curator);
        vault.submit(abi.encodeWithSelector(IVaultV2.setForceReallocateToIdleFee.selector, tooHighFee));
        vm.expectRevert(ErrorsLib.FeeTooHigh.selector);
        vault.setForceReallocateToIdleFee(tooHighFee);
    }

    function testSetLiquidityAdapter(address rdm, address liquidityAdapter) public {
        vm.assume(liquidityAdapter != address(0));
        vm.prank(allocator);
        vm.expectRevert(abi.encodeWithSelector(ErrorsLib.LiquidityAdapterInvariantBroken.selector));
        vault.setLiquidityAdapter(liquidityAdapter);

        vm.prank(curator);
        vault.submit(abi.encodeWithSelector(IVaultV2.setIsAdapter.selector, liquidityAdapter, true));
        vault.setIsAdapter(liquidityAdapter, true);

        // Only allocator can set.
        vm.expectRevert(ErrorsLib.NotAllocator.selector);
        vm.prank(rdm);
        vault.setLiquidityAdapter(liquidityAdapter);

        vm.prank(allocator);
        vm.expectEmit();
        emit EventsLib.SetLiquidityAdapter(allocator, liquidityAdapter);
        vault.setLiquidityAdapter(liquidityAdapter);

        assertEq(vault.liquidityAdapter(), liquidityAdapter);

        vm.prank(curator);
        vault.submit(abi.encodeWithSelector(IVaultV2.setIsAdapter.selector, liquidityAdapter, false));
        vm.expectRevert(abi.encodeWithSelector(ErrorsLib.LiquidityAdapterInvariantBroken.selector));
        vault.setIsAdapter(liquidityAdapter, false);
    }

    function testSetLiquidityData(address rdm) public {
        vm.assume(rdm != owner);
        bytes memory newData = abi.encode("newData");

        vm.expectRevert(ErrorsLib.Unauthorized.selector);
        vm.prank(rdm);
        vault.submit(abi.encodeWithSelector(IVaultV2.setLiquidityData.selector, newData));

        vm.prank(allocator);
        vm.expectEmit();
        emit EventsLib.SetLiquidityData(allocator, newData);
        vault.setLiquidityData(newData);

        assertEq(vault.liquidityData(), newData);
    }
}
