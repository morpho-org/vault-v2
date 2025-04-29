// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import "./BaseTest.sol";
import {VaultV2AddressLib} from "../src/libraries/periphery/VaultV2AddressLib.sol";

contract FactoryTest is BaseTest {
    function testCreateVaultV2(address _owner, address _asset, bytes32 _salt) public {
        address expectedVaultAddress = VaultV2AddressLib.computeVaultV2Address(address(vaultFactory), _owner, _asset, _salt);
        vm.expectEmit();
        emit EventsLib.CreateVaultV2(expectedVaultAddress, _owner, _asset);
        IVaultV2 vault = IVaultV2(vaultFactory.createVaultV2(_owner, _asset, _salt));
        assertEq(address(vault), expectedVaultAddress);
        assertTrue(vaultFactory.isVaultV2(address(vault)));
        assertEq(vault.owner(), _owner);
        assertEq(vault.asset(), _asset);
    }
}
