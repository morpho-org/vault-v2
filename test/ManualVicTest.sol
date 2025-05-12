// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import "../lib/forge-std/src/Test.sol";
import "../src/vic/ManualVic.sol";
import "../src/vic/ManualVicFactory.sol";
import "../src/vic/libraries/periphery/ManualVicAddressLib.sol";
import "./mocks/VaultV2Mock.sol";

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
        manualVic = ManualVic(vicFactory.createManualVic(address(vault), bytes32(0)));
    }

    function testConstructor(address _vault) public {
        vm.assume(_vault != address(vault));
        manualVic = ManualVic(vicFactory.createManualVic(_vault, bytes32(0)));
        assertEq(manualVic.vault(), _vault);
    }

    function testIncreaseMaxInterestPerSecond(address rdm, uint256 newMaxInterestPerSecond) public {
        vm.assume(rdm != curator);
        vm.assume(newMaxInterestPerSecond == 0);

        // Access control.
        vm.prank(rdm);
        vm.expectRevert(ManualVic.Unauthorized.selector);
        manualVic.increaseMaxInterestPerSecond(newMaxInterestPerSecond);

        // Normal path.
        vm.prank(curator);
        vm.expectEmit();
        emit ManualVic.IncreaseMaxInterestPerSecond(newMaxInterestPerSecond);
        manualVic.increaseMaxInterestPerSecond(newMaxInterestPerSecond);
        assertEq(manualVic.maxInterestPerSecond(), newMaxInterestPerSecond);
    }

    function testDecreaseMaxInterestPerSecond(address rdm, uint256 newMaxInterestPerSecond) public {
        vm.assume(rdm != curator && rdm != sentinel);
        vm.assume(newMaxInterestPerSecond == 0);

        vm.prank(curator);
        manualVic.increaseMaxInterestPerSecond(type(uint256).max);

        // Access control.
        vm.prank(rdm);
        vm.expectRevert(ManualVic.Unauthorized.selector);
        manualVic.decreaseMaxInterestPerSecond(newMaxInterestPerSecond);

        // Interest per second too high.
        vm.prank(allocator);
        manualVic.setInterestPerSecond(newMaxInterestPerSecond + 1);
        vm.prank(curator);
        vm.expectRevert(ManualVic.InterestPerSecondTooHigh.selector);
        manualVic.decreaseMaxInterestPerSecond(newMaxInterestPerSecond);

        // Normal path.
        vm.prank(allocator);
        manualVic.setInterestPerSecond(0);
        vm.prank(curator);
        vm.expectEmit();
        emit ManualVic.DecreaseMaxInterestPerSecond(curator, newMaxInterestPerSecond);
        manualVic.decreaseMaxInterestPerSecond(newMaxInterestPerSecond);
        assertEq(manualVic.maxInterestPerSecond(), newMaxInterestPerSecond);
    }

    function testSetInterestPerSecond(address rdm, uint256 newInterestPerSecond) public {
        vm.assume(rdm != allocator && rdm != sentinel);

        vm.prank(curator);
        manualVic.increaseMaxInterestPerSecond(type(uint256).max);

        // Access control.
        vm.prank(rdm);
        vm.expectRevert(ManualVic.Unauthorized.selector);
        manualVic.setInterestPerSecond(newInterestPerSecond);

        // Normal path.
        vm.prank(allocator);
        vm.expectEmit();
        emit ManualVic.SetInterestPerSecond(allocator, newInterestPerSecond);
        manualVic.setInterestPerSecond(newInterestPerSecond);
        assertEq(manualVic.interestPerSecond(0, 0), newInterestPerSecond);
    }

    function testCreateManualVic(address _vault, bytes32 salt) public {
        address expectedManualVicAddress =
            ManualVicAddressLib.computeManualVicAddress(address(vicFactory), _vault, salt);
        vm.expectEmit();
        emit ManualVicFactory.CreateManualVic(expectedManualVicAddress, _vault);
        address newVic = vicFactory.createManualVic(_vault, salt);
        assertEq(newVic, expectedManualVicAddress);
        assertTrue(vicFactory.isManualVic(newVic));
        assertEq(ManualVic(newVic).vault(), _vault);
    }
}
