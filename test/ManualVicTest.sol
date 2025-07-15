// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Morpho Association
pragma solidity ^0.8.0;

import "../lib/forge-std/src/Test.sol";
import "../src/vic/ManualVic.sol";
import "../src/vic/ManualVicFactory.sol";
import "./mocks/VaultV2Mock.sol";
import "../src/vic/interfaces/IManualVic.sol";
import "../src/vic/interfaces/IManualVicFactory.sol";

contract ManualVicTest is Test {
    IManualVicFactory vicFactory;
    ManualVic public manualVic;
    IVaultV2 public vault;
    address public curator;
    address public allocator;
    address public sentinel;

    function setUp() public {
        curator = makeAddr("curator");
        allocator = makeAddr("allocator");
        sentinel = makeAddr("sentinel");
        vault = IVaultV2(address(new VaultV2Mock(address(0), address(0), curator, allocator, sentinel)));
        vicFactory = new ManualVicFactory();
        manualVic = ManualVic(vicFactory.createManualVic(address(vault)));
    }

    function testConstructor(address _vault) public {
        manualVic = ManualVic(new ManualVic(_vault));
        assertEq(manualVic.vault(), _vault);
    }

    function testSetMaxInterestPerSecond(address rdm, uint256 newMaxInterestPerSecond) public {
        vm.assume(rdm != curator);
        vm.assume(newMaxInterestPerSecond > 0);
        vm.assume(newMaxInterestPerSecond <= type(uint96).max);

        // Access control.
        vm.prank(rdm);
        vm.expectRevert(IManualVic.Unauthorized.selector);
        manualVic.setMaxInterestPerSecond(newMaxInterestPerSecond);

        // Cast overflow.
        vm.prank(curator);
        vm.expectRevert(IManualVic.CastOverflow.selector);
        manualVic.setMaxInterestPerSecond(uint256(type(uint96).max) + 1);

        // Normal path, increasing.
        vm.prank(curator);
        vm.expectEmit();
        emit IManualVic.SetMaxInterestPerSecond(newMaxInterestPerSecond);
        manualVic.setMaxInterestPerSecond(newMaxInterestPerSecond);
        assertEq(manualVic.maxInterestPerSecond(), newMaxInterestPerSecond);

        // Interest per second too high.
        vm.prank(allocator);
        manualVic.setInterestPerSecondAndDeadline(newMaxInterestPerSecond, type(uint64).max);
        vm.prank(curator);
        vm.expectRevert(IManualVic.InterestPerSecondTooHigh.selector);
        manualVic.setMaxInterestPerSecond(newMaxInterestPerSecond - 1);

        // Normal path, decreasing.
        vm.prank(allocator);
        manualVic.setInterestPerSecondAndDeadline(0, type(uint64).max);
        vm.prank(curator);
        vm.expectEmit();
        emit IManualVic.SetMaxInterestPerSecond(newMaxInterestPerSecond - 1);
        manualVic.setMaxInterestPerSecond(newMaxInterestPerSecond - 1);
        assertEq(manualVic.maxInterestPerSecond(), newMaxInterestPerSecond - 1);
    }

    function testZeroMaxInterestPerSecond(address rdm, uint256 maxInterestPerSecond) public {
        vm.assume(rdm != sentinel);
        vm.assume(maxInterestPerSecond <= type(uint96).max);
        vm.prank(curator);
        manualVic.setMaxInterestPerSecond(type(uint96).max);

        // Access control.
        vm.prank(rdm);
        vm.expectRevert(IManualVic.Unauthorized.selector);
        manualVic.zeroMaxInterestPerSecond();

        // Interest per second too high.
        vm.prank(allocator);
        manualVic.setInterestPerSecondAndDeadline(1, type(uint64).max);
        vm.prank(sentinel);
        vm.expectRevert(IManualVic.InterestPerSecondTooHigh.selector);
        manualVic.zeroMaxInterestPerSecond();

        // Normal path.
        vm.prank(sentinel);
        manualVic.zeroInterestPerSecondAndDeadline(); // Show that the sentinel can do both.
        vm.prank(sentinel);
        vm.expectEmit();
        emit IManualVic.ZeroMaxInterestPerSecond(sentinel);
        manualVic.zeroMaxInterestPerSecond();
        assertEq(manualVic.maxInterestPerSecond(), 0);
    }

    function testSetInterestPerSecondAndDeadline(address rdm, uint256 newInterestPerSecond, uint256 newDeadline)
        public
    {
        vm.assume(rdm != allocator);
        newInterestPerSecond = bound(newInterestPerSecond, 1, type(uint96).max);
        newDeadline = bound(newDeadline, block.timestamp, type(uint64).max);

        // Access control.
        vm.prank(rdm);
        vm.expectRevert(IManualVic.Unauthorized.selector);
        manualVic.setInterestPerSecondAndDeadline(newInterestPerSecond, newDeadline);

        // Greater than max interest per second.
        vm.prank(allocator);
        vm.expectRevert(IManualVic.InterestPerSecondTooHigh.selector);
        manualVic.setInterestPerSecondAndDeadline(1, newDeadline);

        vm.prank(curator);
        manualVic.setMaxInterestPerSecond(type(uint96).max);

        // Deadline already passed.
        vm.prank(allocator);
        vm.expectRevert(IManualVic.DeadlineAlreadyPassed.selector);
        manualVic.setInterestPerSecondAndDeadline(newInterestPerSecond, block.timestamp - 1);

        // Deadline cast overflow.
        vm.prank(allocator);
        vm.expectRevert(IManualVic.CastOverflow.selector);
        manualVic.setInterestPerSecondAndDeadline(newInterestPerSecond, uint256(type(uint64).max) + 1);

        // Normal path, increasing.
        vm.prank(allocator);
        vm.expectEmit();
        emit IManualVic.SetInterestPerSecondAndDeadline(allocator, newInterestPerSecond, newDeadline);
        manualVic.setInterestPerSecondAndDeadline(newInterestPerSecond, newDeadline);
        assertEq(manualVic.interestPerSecond(0, 0), newInterestPerSecond);
        assertEq(manualVic.storedInterestPerSecond(), newInterestPerSecond);
        assertEq(manualVic.deadline(), newDeadline);

        // Normal path, decreasing.
        vm.prank(allocator);
        manualVic.setInterestPerSecondAndDeadline(newInterestPerSecond - 1, newDeadline);
        assertEq(manualVic.interestPerSecond(0, 0), newInterestPerSecond - 1);
        assertEq(manualVic.storedInterestPerSecond(), newInterestPerSecond - 1);
        assertEq(manualVic.deadline(), newDeadline);
    }

    function testZeroInterestPerSecondAndDeadline(address rdm) public {
        vm.assume(rdm != sentinel);

        // Access control.
        vm.prank(rdm);
        vm.expectRevert(IManualVic.Unauthorized.selector);
        manualVic.zeroInterestPerSecondAndDeadline();

        // Normal path.
        vm.prank(curator);
        manualVic.setMaxInterestPerSecond(type(uint96).max);
        vm.prank(allocator);
        manualVic.setInterestPerSecondAndDeadline(1, type(uint64).max);
        vm.prank(sentinel);
        vm.expectEmit();
        emit IManualVic.ZeroInterestPerSecondAndDeadline(sentinel);
        manualVic.zeroInterestPerSecondAndDeadline();
        assertEq(manualVic.interestPerSecond(0, 0), 0);
        assertEq(manualVic.storedInterestPerSecond(), 0);
        assertEq(manualVic.deadline(), 0);
    }

    function testDeadline(uint256 newDeadline) public {
        newDeadline = bound(newDeadline, block.timestamp, type(uint64).max - 1);

        // Setup.
        vm.prank(curator);
        manualVic.setMaxInterestPerSecond(type(uint96).max);
        vm.prank(allocator);
        manualVic.setInterestPerSecondAndDeadline(1, newDeadline);

        // Before deadline.
        vm.warp(newDeadline - 1);
        assertEq(manualVic.interestPerSecond(0, 0), 1);

        // Past deadline.
        vm.warp(newDeadline + 1);
        assertEq(manualVic.interestPerSecond(0, 0), 0);
    }

    function testCreateManualVic(address _vault) public {
        vm.assume(_vault != address(vault));
        bytes32 initCodeHash = keccak256(abi.encodePacked(type(ManualVic).creationCode, abi.encode(_vault)));
        address expectedManualVicAddress = address(
            uint160(uint256(keccak256(abi.encodePacked(uint8(0xff), address(vicFactory), bytes32(0), initCodeHash))))
        );
        vm.expectEmit();
        emit IManualVicFactory.CreateManualVic(expectedManualVicAddress, _vault);
        address newVic = vicFactory.createManualVic(_vault);
        assertEq(newVic, expectedManualVicAddress);
        assertTrue(vicFactory.isManualVic(newVic));
        assertEq(vicFactory.manualVic(_vault), newVic);
        assertEq(IManualVic(newVic).vault(), _vault);
    }
}
