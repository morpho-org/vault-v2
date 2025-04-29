// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import "./BaseTest.sol";

contract MulticallTest is BaseTest {
    function testMulticall(address newCurator, address newOwner) public {
        bytes[] memory data = new bytes[](2);
        data[0] = abi.encodeWithSelector(
            IVaultV2.submit.selector, abi.encodeWithSelector(IVaultV2.setCurator.selector, newCurator)
        );
        data[1] = abi.encodeWithSelector(
            IVaultV2.submit.selector, abi.encodeWithSelector(IVaultV2.setOwner.selector, newOwner)
        );

        vm.prank(owner);
        vault.multicall(data);

        vault.setCurator(newCurator);
        vault.setOwner(newOwner);

        assertEq(vault.curator(), newCurator, "wrong curator");
        assertEq(vault.owner(), newOwner, "wrong owner");
    }
}
