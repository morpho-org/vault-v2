// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import "../lib/forge-std/src/Test.sol";
import "../src/interest-controllers/ManualInterestController.sol";
import "../src/libraries/ErrorsLib.sol";

contract ManualInterestControllerTest is Test {
    ManualInterestController public manualInterestController;

    function setUp() public {
        manualInterestController = new ManualInterestController(address(this));
    }

    function testConstructor(address owner) public {
        manualInterestController = new ManualInterestController(owner);
        assertEq(manualInterestController.owner(), owner);
    }

    function testSetInterestPerSecond(address rdm, uint256 newInterestPerSecond) public {
        vm.assume(rdm != address(this));

        // Access control.
        vm.prank(rdm);
        vm.expectRevert(ErrorsLib.Unauthorized.selector);
        manualInterestController.setInterestPerSecond(newInterestPerSecond);

        // Normal path.
        vm.expectEmit();
        emit EventsLib.SetInterestPerSecond(newInterestPerSecond);
        manualInterestController.setInterestPerSecond(newInterestPerSecond);
        assertEq(manualInterestController.interestPerSecond(0, 0), newInterestPerSecond);
    }
}
