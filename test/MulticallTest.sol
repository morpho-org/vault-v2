// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import "./BaseTest.sol";

contract MulticallTest is BaseTest {
    function testMulticall(address newCurator, address newOwner) public {
        bytes[] memory data = new bytes[](2);
        data[0] = abi.encodeWithSelector(IVaultV2.setCurator.selector, newCurator);
        data[1] = abi.encodeWithSelector(IVaultV2.setOwner.selector, newOwner);

        vm.prank(owner);
        vault.multicall(data);

        assertEq(vault.curator(), newCurator, "wrong curator");
        assertEq(vault.owner(), newOwner, "wrong owner");
    }

    function testMulticallFailing(address rdm) public {
        vm.assume(rdm != curator);

        bytes[] memory data = new bytes[](2);
        data[0] = abi.encodeWithSelector(IVaultV2.setCurator.selector, address(1));
        data[1] = abi.encodeWithSelector(IVaultV2.submit.selector, hex"");
        vm.prank(rdm);
        vm.expectRevert(ErrorsLib.Unauthorized.selector);
        vault.multicall(data);
    }
}
