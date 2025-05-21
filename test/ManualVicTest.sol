// SPDX-License-Identifier: GPL-2.0-or-later
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

    function testIncreaseMaxInterestPerSecond(address rdm, uint256 newMaxInterestPerSecond) public {
        vm.assume(rdm != curator);
        vm.assume(newMaxInterestPerSecond > 0);

        // Access control.
        vm.prank(rdm);
        vm.expectRevert(IManualVic.Unauthorized.selector);
        manualVic.increaseMaxInterestPerSecond(newMaxInterestPerSecond);

        // Normal path.
        vm.prank(curator);
        vm.expectEmit();
        emit IManualVic.IncreaseMaxInterestPerSecond(newMaxInterestPerSecond);
        manualVic.increaseMaxInterestPerSecond(newMaxInterestPerSecond);
        assertEq(manualVic.maxInterestPerSecond(), newMaxInterestPerSecond);

        // Not increasing.
        vm.prank(curator);
        vm.expectRevert(IManualVic.NotIncreasing.selector);
        manualVic.increaseMaxInterestPerSecond(newMaxInterestPerSecond - 1);
    }

    function testDecreaseMaxInterestPerSecond(address rdm, uint256 newMaxInterestPerSecond) public {
        vm.assume(rdm != curator && rdm != sentinel);
        vm.assume(newMaxInterestPerSecond < type(uint256).max);
        vm.prank(curator);
        manualVic.increaseMaxInterestPerSecond(type(uint256).max);

        // Access control.
        vm.prank(rdm);
        vm.expectRevert(IManualVic.Unauthorized.selector);
        manualVic.decreaseMaxInterestPerSecond(newMaxInterestPerSecond);

        // Interest per second too high.
        vm.prank(allocator);
        manualVic.increaseInterestPerSecond(newMaxInterestPerSecond + 1);
        vm.prank(curator);
        vm.expectRevert(IManualVic.InterestPerSecondTooHigh.selector);
        manualVic.decreaseMaxInterestPerSecond(newMaxInterestPerSecond);

        // Normal path.
        vm.prank(allocator);
        manualVic.decreaseInterestPerSecond(0);
        vm.prank(curator);
        vm.expectEmit();
        emit IManualVic.DecreaseMaxInterestPerSecond(curator, newMaxInterestPerSecond);
        manualVic.decreaseMaxInterestPerSecond(newMaxInterestPerSecond);
        assertEq(manualVic.maxInterestPerSecond(), newMaxInterestPerSecond);

        // Not decreasing.
        vm.prank(curator);
        vm.expectRevert(IManualVic.NotDecreasing.selector);
        manualVic.decreaseMaxInterestPerSecond(newMaxInterestPerSecond + 1);
    }

    function testIncreaseInterestPerSecond(address rdm, uint256 newInterestPerSecond) public {
        vm.assume(rdm != allocator);

        // Access control.
        vm.prank(rdm);
        vm.expectRevert(IManualVic.Unauthorized.selector);
        manualVic.increaseInterestPerSecond(newInterestPerSecond);

        // Greater than max interest per second.
        vm.prank(allocator);
        vm.expectRevert(IManualVic.InterestPerSecondTooHigh.selector);
        manualVic.increaseInterestPerSecond(bound(newInterestPerSecond, 1, type(uint256).max));

        // Normal path.
        vm.prank(curator);
        manualVic.increaseMaxInterestPerSecond(type(uint256).max);
        vm.prank(allocator);
        vm.expectEmit();
        emit IManualVic.IncreaseInterestPerSecond(allocator, newInterestPerSecond);
        manualVic.increaseInterestPerSecond(newInterestPerSecond);
        assertEq(manualVic.interestPerSecond(0, 0), newInterestPerSecond);
    }

    function testDecreaseInterestPerSecond(address rdm, uint256 newInterestPerSecond) public {
        vm.assume(rdm != allocator && rdm != sentinel);

        // Access control.
        vm.prank(rdm);
        vm.expectRevert(IManualVic.Unauthorized.selector);
        manualVic.decreaseInterestPerSecond(newInterestPerSecond);

        // Greater than max interest per second.
        vm.prank(allocator);
        vm.expectRevert(IManualVic.InterestPerSecondTooHigh.selector);
        manualVic.decreaseInterestPerSecond(bound(newInterestPerSecond, 1, type(uint256).max));

        // Normal path.
        vm.prank(curator);
        manualVic.increaseMaxInterestPerSecond(type(uint256).max);
        vm.prank(allocator);
        manualVic.increaseInterestPerSecond(type(uint256).max);
        vm.expectEmit();
        emit IManualVic.DecreaseInterestPerSecond(allocator, newInterestPerSecond);
        vm.prank(allocator);
        manualVic.decreaseInterestPerSecond(newInterestPerSecond);
        assertEq(manualVic.interestPerSecond(0, 0), newInterestPerSecond);
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
