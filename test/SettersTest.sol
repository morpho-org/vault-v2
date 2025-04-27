// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import "./BaseTest.sol";
import {EventsLib} from "../src/libraries/EventsLib.sol";

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

        // Nobody can set directly
        vm.expectRevert(ErrorsLib.DataNotTimelocked.selector);
        vault.setOwner(newOwner);

        // Only owner can submit
        vm.expectRevert(ErrorsLib.Unauthorized.selector);
        vm.prank(rdm);
        vault.submit(abi.encodeWithSelector(IVaultV2.setOwner.selector, newOwner));

        vm.prank(owner);
        vault.submit(abi.encodeWithSelector(IVaultV2.setOwner.selector, newOwner));

        vm.expectEmit();
        emit EventsLib.SetOwner(newOwner);
        vault.setOwner(newOwner);

        assertEq(vault.owner(), newOwner);
    }

    function testSetCurator(address rdm) public {
        vm.assume(rdm != owner);
        address newCurator = makeAddr("newCurator");

        // Nobody can set directly
        vm.expectRevert(ErrorsLib.DataNotTimelocked.selector);
        vault.setCurator(newCurator);

        // Only owner can submit
        vm.expectRevert(ErrorsLib.Unauthorized.selector);
        vm.prank(rdm);
        vault.submit(abi.encodeWithSelector(IVaultV2.setCurator.selector, newCurator));

        vm.prank(owner);
        vault.submit(abi.encodeWithSelector(IVaultV2.setCurator.selector, newCurator));

        vm.expectEmit();
        emit EventsLib.SetCurator(newCurator);
        vault.setCurator(newCurator);

        assertEq(vault.curator(), newCurator);
    }

    function testSetIRM(address rdm) public {
        vm.assume(rdm != owner);
        address newIRM = address(new IRM(manager));

        // Nobody can set directly
        vm.expectRevert(ErrorsLib.DataNotTimelocked.selector);
        vault.setIRM(newIRM);

        // Only owner can submit
        vm.expectRevert(ErrorsLib.Unauthorized.selector);
        vm.prank(rdm);
        vault.submit(abi.encodeWithSelector(IVaultV2.setIRM.selector, newIRM));

        vm.prank(owner);
        vault.submit(abi.encodeWithSelector(IVaultV2.setIRM.selector, newIRM));

        vm.expectEmit();
        emit EventsLib.SetIRM(newIRM);
        vault.setIRM(newIRM);

        assertEq(address(vault.irm()), newIRM);
    }

    function testSetIsAllocator(address rdm) public {
        vm.assume(rdm != owner);
        address newAllocator = makeAddr("newAllocator");

        // Nobody can set directly
        vm.expectRevert(ErrorsLib.DataNotTimelocked.selector);
        vault.setIsAllocator(newAllocator, true);

        // Only owner can submit
        vm.expectRevert(ErrorsLib.Unauthorized.selector);
        vm.prank(rdm);
        vault.submit(abi.encodeWithSelector(IVaultV2.setIsAllocator.selector, newAllocator, true));

        vm.prank(owner);
        vault.submit(abi.encodeWithSelector(IVaultV2.setIsAllocator.selector, newAllocator, true));

        vm.expectEmit();
        emit EventsLib.SetIsAllocator(newAllocator, true);
        vault.setIsAllocator(newAllocator, true);

        assertTrue(vault.isAllocator(newAllocator));

        // Owner can remove an allocator
        vm.prank(owner);
        vault.submit(abi.encodeWithSelector(IVaultV2.setIsAllocator.selector, newAllocator, false));
        vault.setIsAllocator(newAllocator, false);

        assertFalse(vault.isAllocator(newAllocator));
    }

    function testSetPerformanceFee(address rdm, uint256 newPerformanceFee) public {
        vm.assume(rdm != treasurer);
        newPerformanceFee = bound(newPerformanceFee, 0, MAX_PERFORMANCE_FEE);

        // Nobody can set directly
        vm.expectRevert(ErrorsLib.DataNotTimelocked.selector);
        vault.setPerformanceFee(newPerformanceFee);

        // Only treasurer can submit
        vm.expectRevert(ErrorsLib.Unauthorized.selector);
        vm.prank(rdm);
        vault.submit(abi.encodeWithSelector(IVaultV2.setPerformanceFee.selector, newPerformanceFee));

        uint256 tooHighFee = 1 ether + 1;
        vm.prank(treasurer);
        vault.submit(abi.encodeWithSelector(IVaultV2.setPerformanceFee.selector, tooHighFee));

        vm.expectRevert(ErrorsLib.FeeTooHigh.selector);
        vault.setPerformanceFee(tooHighFee);

        vm.prank(treasurer);
        vault.submit(abi.encodeWithSelector(IVaultV2.setPerformanceFee.selector, newPerformanceFee));

        assertEq(
            vault.validAt(abi.encodeWithSelector(IVaultV2.setPerformanceFee.selector, newPerformanceFee)),
            block.timestamp
        );

        vm.expectRevert(ErrorsLib.FeeInvariantBroken.selector);
        vault.setPerformanceFee(newPerformanceFee);

        vm.prank(owner);
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
        vm.assume(rdm != owner);
        vm.assume(newPerformanceFeeRecipient != address(0));

        // Nobody can set directly
        vm.expectRevert(ErrorsLib.DataNotTimelocked.selector);
        vault.setPerformanceFeeRecipient(newPerformanceFeeRecipient);

        // Only owner can submit
        vm.expectRevert(ErrorsLib.Unauthorized.selector);
        vm.prank(rdm);
        vault.submit(abi.encodeWithSelector(IVaultV2.setPerformanceFeeRecipient.selector, newPerformanceFeeRecipient));

        vm.prank(owner);
        vault.submit(abi.encodeWithSelector(IVaultV2.setPerformanceFeeRecipient.selector, newPerformanceFeeRecipient));
        vm.expectEmit();
        emit EventsLib.SetPerformanceFeeRecipient(newPerformanceFeeRecipient);
        vault.setPerformanceFeeRecipient(newPerformanceFeeRecipient);

        assertEq(vault.performanceFeeRecipient(), newPerformanceFeeRecipient);

        uint256 newPerformanceFee = 0.05 ether;
        vm.prank(treasurer);
        vault.submit(abi.encodeWithSelector(IVaultV2.setPerformanceFee.selector, newPerformanceFee));
        vault.setPerformanceFee(newPerformanceFee);

        vm.prank(owner);
        vault.submit(abi.encodeWithSelector(IVaultV2.setPerformanceFeeRecipient.selector, address(0)));
        vm.expectRevert(ErrorsLib.FeeInvariantBroken.selector);
        vault.setPerformanceFeeRecipient(address(0));
    }

    function testSetManagementFee(address rdm, uint256 newManagementFee) public {
        vm.assume(rdm != treasurer);
        newManagementFee = bound(newManagementFee, 0, MAX_MANAGEMENT_FEE);

        // Nobody can set directly
        vm.expectRevert(ErrorsLib.DataNotTimelocked.selector);
        vault.setManagementFee(newManagementFee);

        // Only treasurer can submit
        vm.expectRevert(ErrorsLib.Unauthorized.selector);
        vm.prank(rdm);
        vault.submit(abi.encodeWithSelector(IVaultV2.setManagementFee.selector, newManagementFee));

        uint256 tooHighFee = 1 ether + 1;
        vm.prank(treasurer);
        vault.submit(abi.encodeWithSelector(IVaultV2.setManagementFee.selector, tooHighFee));
        vm.expectRevert(ErrorsLib.FeeTooHigh.selector);
        vault.setManagementFee(tooHighFee);

        vm.prank(treasurer);
        vault.submit(abi.encodeWithSelector(IVaultV2.setManagementFee.selector, newManagementFee));

        assertEq(
            vault.validAt(abi.encodeWithSelector(IVaultV2.setManagementFee.selector, newManagementFee)), block.timestamp
        );

        vm.expectRevert(ErrorsLib.FeeInvariantBroken.selector);
        vault.setManagementFee(newManagementFee);

        vm.prank(owner);
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
        vm.assume(rdm != owner);
        vm.assume(newManagementFeeRecipient != address(0));

        // Nobody can set directly
        vm.expectRevert(ErrorsLib.DataNotTimelocked.selector);
        vault.setManagementFeeRecipient(newManagementFeeRecipient);

        // Only owner can submit
        vm.expectRevert(ErrorsLib.Unauthorized.selector);
        vm.prank(rdm);
        vault.submit(abi.encodeWithSelector(IVaultV2.setManagementFeeRecipient.selector, newManagementFeeRecipient));

        vm.prank(owner);
        vault.submit(abi.encodeWithSelector(IVaultV2.setManagementFeeRecipient.selector, newManagementFeeRecipient));
        vm.expectEmit();
        emit EventsLib.SetManagementFeeRecipient(newManagementFeeRecipient);
        vault.setManagementFeeRecipient(newManagementFeeRecipient);

        assertEq(vault.managementFeeRecipient(), newManagementFeeRecipient);

        uint256 newManagementFee = 0.01 ether / uint256(365.25 days);
        vm.prank(treasurer);
        vault.submit(abi.encodeWithSelector(IVaultV2.setManagementFee.selector, newManagementFee));
        vault.setManagementFee(newManagementFee);

        vm.prank(owner);
        vault.submit(abi.encodeWithSelector(IVaultV2.setManagementFeeRecipient.selector, address(0)));
        vm.expectRevert(ErrorsLib.FeeInvariantBroken.selector);
        vault.setManagementFeeRecipient(address(0));
    }
}
