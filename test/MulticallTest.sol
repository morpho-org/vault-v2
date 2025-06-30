// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Morpho Association
pragma solidity ^0.8.0;

import "./BaseTest.sol";

contract MulticallTest is BaseTest {
    function testMulticall(address newCurator, address newOwner) public {
        bytes[] memory data = new bytes[](2);
        data[0] = abi.encodeCall(IVaultV2.setCurator, (newCurator));
        data[1] = abi.encodeCall(IVaultV2.setOwner, (newOwner));

        vm.prank(owner);
        vault.multicall(data);

        assertEq(vault.curator(), newCurator, "wrong curator");
        assertEq(vault.owner(), newOwner, "wrong owner");
    }

    function testMulticallFailing(address rdm) public {
        vm.assume(rdm != curator);

        bytes[] memory data = new bytes[](2);
        data[0] = abi.encodeCall(IVaultV2.setCurator, (address(1)));
        data[1] = abi.encodeCall(IVaultV2.submit, (hex""));
        vm.prank(rdm);
        vm.expectRevert(ErrorsLib.Unauthorized.selector);
        vault.multicall(data);
    }

    function testMulticallEmpty() public {
        vm.prank(curator);
        vault.multicall(new bytes[](0));
    }
}
