// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.28;

import "./BaseTest.sol";

contract SettersTest is BaseTest {
    function testConstructor() public view {
        assertEq(address(vault.asset()), address(underlyingToken));
        assertEq(address(vault.irm()), address(irm));
        assertEq(irm.owner(), manager);
    }

    function testSetOwner(address rdm) public {
        vm.assume(rdm != owner);
        address newOwner = makeAddr("newOwner");

        // Nobody can set directly
        vm.expectRevert(ErrorsLib.DataNotTimelocked.selector);
        vault.setRoles(newOwner, OWNER);

        // Only owner can submit
        vm.expectRevert(ErrorsLib.Unauthorized.selector);
        vm.prank(rdm);
        vault.submit(abi.encodeWithSelector(IVaultV2.setRoles.selector, newOwner, OWNER));

        vm.prank(owner);
        vault.submit(abi.encodeWithSelector(IVaultV2.setRoles.selector, newOwner, OWNER));
        vault.setRoles(newOwner, OWNER);

        assertEq(vault.hasRole(newOwner, OWNER), true);
    }

    function testSetCurator(address rdm) public {
        vm.assume(rdm != owner);
        address newCurator = makeAddr("newCurator");

        // Nobody can set directly
        vm.expectRevert(ErrorsLib.DataNotTimelocked.selector);
        vault.setRoles(newCurator, CURATOR);

        // Only owner can submit
        vm.expectRevert(ErrorsLib.Unauthorized.selector);
        vm.prank(rdm);
        vault.submit(abi.encodeWithSelector(IVaultV2.setRoles.selector, newCurator, CURATOR));

        vm.prank(owner);
        vault.submit(abi.encodeWithSelector(IVaultV2.setRoles.selector, newCurator, CURATOR));
        vault.setRoles(newCurator, CURATOR);

        assertEq(vault.hasRole(newCurator, CURATOR), true);
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
        vault.setIRM(newIRM);

        assertEq(address(vault.irm()), newIRM);
    }

    function testSetIsAllocator(address rdm) public {
        vm.assume(rdm != owner);
        address newAllocator = makeAddr("newAllocator");

        // Nobody can set directly
        vm.expectRevert(ErrorsLib.DataNotTimelocked.selector);
        vault.setRoles(newAllocator, ALLOCATOR);

        // Only owner can submit
        vm.expectRevert(ErrorsLib.Unauthorized.selector);
        vm.prank(rdm);
        vault.submit(abi.encodeWithSelector(IVaultV2.setRoles.selector, newAllocator, ALLOCATOR));

        vm.prank(owner);
        vault.submit(abi.encodeWithSelector(IVaultV2.setRoles.selector, newAllocator, ALLOCATOR));
        vault.setRoles(newAllocator, ALLOCATOR);

        assertEq(vault.hasRole(newAllocator, ALLOCATOR), true);

        // Owner can remove an allocator
        vm.prank(owner);
        vault.submit(abi.encodeWithSelector(IVaultV2.setRoles.selector, newAllocator, 0));
        vault.setRoles(newAllocator, 0);

        assertEq(vault.hasRole(newAllocator, ALLOCATOR), false);
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
