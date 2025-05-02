// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import "./BaseTest.sol";
import {VaultV2AddressLib} from "../src/libraries/periphery/VaultV2AddressLib.sol";
import {IrmAddressLib} from "../src/libraries/periphery/IrmAddressLib.sol";

contract FactoryTest is BaseTest {
    event CreateIrm(address indexed irm, address indexed owner);

    function testCreateIrm(address _owner, bytes32 _salt) public {
        address expectedIrmAddress = IrmAddressLib.computeIrmAddress(address(irmFactory), _owner, _salt);
        vm.expectEmit();
        emit CreateIrm(expectedIrmAddress, _owner);
        IRM irm = IRM(irmFactory.createIrm(_owner, _salt));
        assertEq(address(irm), expectedIrmAddress);
        assertTrue(irmFactory.isIrm(address(irm)));
        assertEq(irm.owner(), _owner);
    }
}
