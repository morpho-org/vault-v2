// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import "./BaseTest.sol";
import {VaultV2AddressLib} from "../src/libraries/periphery/VaultV2AddressLib.sol";

contract FactoryTest is BaseTest {
    function testCreateVaultV2(address _owner, address asset, bytes32 salt) public {
        address expectedVaultAddress =
            VaultV2AddressLib.computeVaultV2Address(address(vaultFactory), _owner, asset, salt);
        vm.expectEmit();
        emit EventsLib.Constructor(_owner, asset);
        vm.expectEmit();
        emit EventsLib.CreateVaultV2(expectedVaultAddress, asset);
        IVaultV2 newVault = IVaultV2(vaultFactory.createVaultV2(_owner, asset, salt));
        assertEq(address(newVault), expectedVaultAddress);
        assertTrue(vaultFactory.isVaultV2(address(newVault)));
        assertEq(newVault.owner(), _owner);
        assertEq(newVault.asset(), asset);
    }
}
