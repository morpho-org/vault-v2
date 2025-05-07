// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import "./BaseTest.sol";
import {VaultV2AddressLib} from "../src/libraries/periphery/VaultV2AddressLib.sol";
import {ManualInterestControllerAddressLib} from
    "../src/interest-controllers/libraries/periphery/ManualInterestControllerAddressLib.sol";

contract FactoryTest is BaseTest {
    function testCreateVaultV2(address _owner, address asset, bytes32 salt) public {
        address expectedVaultAddress =
            VaultV2AddressLib.computeVaultV2Address(address(vaultFactory), _owner, asset, salt);
        vm.expectEmit();
        emit EventsLib.Construction(_owner, asset);
        vm.expectEmit();
        emit EventsLib.CreateVaultV2(expectedVaultAddress, _owner, asset);
        IVaultV2 newVault = IVaultV2(vaultFactory.createVaultV2(_owner, asset, salt));
        assertEq(address(newVault), expectedVaultAddress);
        assertTrue(vaultFactory.isVaultV2(address(newVault)));
        assertEq(newVault.owner(), _owner);
        assertEq(newVault.asset(), asset);
    }

    function testCreateManualInterestController(address _owner, bytes32 salt) public {
        address expectedManualInterestControllerAddress = ManualInterestControllerAddressLib
            .computeManualInterestControllerAddress(address(interestControllerFactory), _owner, salt);
        vm.expectEmit();
        emit ManualInterestControllerFactory.CreateManualInterestController(
            expectedManualInterestControllerAddress, _owner
        );
        address newInterestController = interestControllerFactory.createManualInterestController(_owner, salt);
        assertEq(newInterestController, expectedManualInterestControllerAddress);
        assertTrue(interestControllerFactory.isManualInterestController(newInterestController));
        assertEq(ManualInterestController(newInterestController).owner(), _owner);
    }
}
