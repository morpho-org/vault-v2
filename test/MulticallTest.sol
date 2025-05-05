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

    function testFailingMulticall() public {
        bytes[] memory data = new bytes[](2);
        data[0] = abi.encodeWithSelector(IVaultV2.decreaseAbsoluteCap.selector, keccak256(abi.encode(address(1))), 0);
        data[1] = abi.encodeWithSelector(IVaultV2.setOwner.selector, address(1));

        vm.prank(curator);
        vm.expectRevert(ErrorsLib.Unauthorized.selector);
        vault.multicall(data);
    }
}
