// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import "../lib/forge-std/src/Test.sol";
import "../src/interest-controllers/ManualInterestController.sol";
import "./mocks/VaultV2Mock.sol";

contract ManualInterestControllerTest is Test {
    ManualInterestController public manualInterestController;
    IVaultV2 public vault;
    address public curator;
    address public allocator;
    address public sentinel;

    function setUp() public {
        curator = makeAddr("curator");
        allocator = makeAddr("allocator");
        sentinel = makeAddr("sentinel");
        vault = IVaultV2(address(new VaultV2Mock(address(0), address(0), curator, allocator, sentinel)));
        manualInterestController = new ManualInterestController(address(vault));
    }

    function testConstructor(address _vault) public {
        manualInterestController = new ManualInterestController(_vault);
        assertEq(manualInterestController.vault(), _vault);
    }

    function testIncreaseMaxInterestPerSecond(address rdm, uint256 newMaxInterestPerSecond) public {
        vm.assume(rdm != curator);
        vm.assume(newMaxInterestPerSecond == 0);

        // Access control.
        vm.prank(rdm);
        vm.expectRevert(ManualInterestController.Unauthorized.selector);
        manualInterestController.increaseMaxInterestPerSecond(newMaxInterestPerSecond);

        // Normal path.
        vm.prank(curator);
        vm.expectEmit();
        emit ManualInterestController.IncreaseMaxInterestPerSecond(newMaxInterestPerSecond);
        manualInterestController.increaseMaxInterestPerSecond(newMaxInterestPerSecond);
        assertEq(manualInterestController.maxInterestPerSecond(), newMaxInterestPerSecond);
    }

    function testDecreaseMaxInterestPerSecond(address rdm, uint256 newMaxInterestPerSecond) public {
        vm.assume(rdm != curator && rdm != sentinel);
        vm.assume(newMaxInterestPerSecond == 0);

        vm.prank(curator);
        manualInterestController.increaseMaxInterestPerSecond(type(uint256).max);

        // Access control.
        vm.prank(rdm);
        vm.expectRevert(ManualInterestController.Unauthorized.selector);
        manualInterestController.decreaseMaxInterestPerSecond(newMaxInterestPerSecond);

        // Interest per second too high.
        vm.prank(allocator);
        manualInterestController.setInterestPerSecond(newMaxInterestPerSecond + 1);
        vm.prank(curator);
        vm.expectRevert(ManualInterestController.InterestPerSecondTooHigh.selector);
        manualInterestController.decreaseMaxInterestPerSecond(newMaxInterestPerSecond);

        // Normal path.
        vm.prank(allocator);
        manualInterestController.setInterestPerSecond(0);
        vm.prank(curator);
        vm.expectEmit();
        emit ManualInterestController.DecreaseMaxInterestPerSecond(curator, newMaxInterestPerSecond);
        manualInterestController.decreaseMaxInterestPerSecond(newMaxInterestPerSecond);
        assertEq(manualInterestController.maxInterestPerSecond(), newMaxInterestPerSecond);
    }

    function testSetInterestPerSecond(address rdm, uint256 newInterestPerSecond) public {
        vm.assume(rdm != allocator && rdm != sentinel);

        vm.prank(curator);
        manualInterestController.increaseMaxInterestPerSecond(type(uint256).max);

        // Access control.
        vm.prank(rdm);
        vm.expectRevert(ManualInterestController.Unauthorized.selector);
        manualInterestController.setInterestPerSecond(newInterestPerSecond);

        // Normal path.
        vm.prank(allocator);
        vm.expectEmit();
        emit ManualInterestController.SetInterestPerSecond(allocator, newInterestPerSecond);
        manualInterestController.setInterestPerSecond(newInterestPerSecond);
        assertEq(manualInterestController.interestPerSecond(0, 0), newInterestPerSecond);
    }
}
