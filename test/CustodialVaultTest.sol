// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import {BaseTest, VaultsV2, EncodeLib} from "./BaseTest.sol";

contract CustodialVaultTest is BaseTest {
    function testRevertNonManager(address caller) public {
        vm.assume(caller != manager);
        bundle.push(EncodeLib.setIRMCall(address(0)));
        vm.prank(caller);
        vm.expectRevert(VaultsV2.UnauthorizedMulticall.selector);
        vault.multiCall(bundle);
    }

    function testManager() public {
        bundle.push(EncodeLib.setIRMCall(address(0)));
        vm.prank(manager);
        vault.multiCall(bundle);
    }
}
