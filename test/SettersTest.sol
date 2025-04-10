// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.28;

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
        vault.setOwner(newOwner);

        assertEq(vault.owner(), newOwner);
    }

    function testSetCurator(address rdm) public {
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
        vault.setIRM(newIRM);

        assertEq(address(vault.irm()), newIRM);
    }

    function testSetIsAllocator(address rdm) public {
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
        vault.setIsAllocator(newAllocator, true);

        assertTrue(vault.isAllocator(newAllocator));

        // Owner can remove an allocator
        vm.prank(owner);
        vault.submit(abi.encodeWithSelector(IVaultV2.setIsAllocator.selector, newAllocator, false));
        vault.setIsAllocator(newAllocator, false);

        assertFalse(vault.isAllocator(newAllocator));
    }

    function testSetPerformanceFee(address rdm) public {
        uint256 newPerformanceFee = 500; // 5%

        // Nobody can set directly
        vm.expectRevert(ErrorsLib.DataNotTimelocked.selector);
        vault.setPerformanceFee(newPerformanceFee);

        // Only owner can submit
        vm.expectRevert(ErrorsLib.Unauthorized.selector);
        vm.prank(rdm);
        vault.submit(abi.encodeWithSelector(IVaultV2.setPerformanceFee.selector, newPerformanceFee));

        uint256 tooHighFee = 1 ether + 1;
        vm.prank(treasurer);
        vault.submit(abi.encodeWithSelector(IVaultV2.setPerformanceFee.selector, tooHighFee));
        vm.expectRevert();
        vault.setPerformanceFee(tooHighFee);

        vm.prank(treasurer);
        vault.submit(abi.encodeWithSelector(IVaultV2.setPerformanceFee.selector, newPerformanceFee));
        vault.setPerformanceFee(newPerformanceFee);

        assertEq(vault.performanceFee(), newPerformanceFee);
    }

    function testSetPerformanceFeeRecipient(address rdm) public {
        address newPerformanceFeeRecipient = makeAddr("newPerformanceFeeRecipient");

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
    }

    function testSetManagementFee(address rdm) public {
        uint256 newManagementFee = 500; // 5%

        // Nobody can set directly
        vm.expectRevert(ErrorsLib.DataNotTimelocked.selector);
        vault.setManagementFee(newManagementFee);

        // Only owner can submit
        vm.expectRevert(ErrorsLib.Unauthorized.selector);
        vm.prank(rdm);
        vault.submit(abi.encodeWithSelector(IVaultV2.setManagementFee.selector, newManagementFee));

        uint256 tooHighFee = 1 ether + 1;
        vm.prank(treasurer);
        vault.submit(abi.encodeWithSelector(IVaultV2.setManagementFee.selector, tooHighFee));
        vm.expectRevert();
        vault.setManagementFee(tooHighFee);

        vm.prank(treasurer);
        vault.submit(abi.encodeWithSelector(IVaultV2.setManagementFee.selector, newManagementFee));
        vault.setManagementFee(newManagementFee);

        assertEq(vault.managementFee(), newManagementFee);
    }

    function testSetManagementFeeRecipient(address rdm) public {
        address newManagementFeeRecipient = makeAddr("newManagementFeeRecipient");

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
    }
}
