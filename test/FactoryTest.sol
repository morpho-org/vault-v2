// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import "./BaseTest.sol";
import {VaultV2AddressLib} from "../src/libraries/periphery/VaultV2AddressLib.sol";
import {
    ManualInterestControllerFactory,
    ManualInterestController
} from "../src/interest-controllers/ManualInterestControllerFactory.sol";
import {IInterestController} from "../src/interfaces/IInterestController.sol";

contract FactoryTest is BaseTest {
    function testCreateVaultV2(address _owner, address _asset, bytes32 _salt) public {
        address expectedVaultAddress =
            VaultV2AddressLib.computeVaultV2Address(address(vaultFactory), _owner, _asset, _salt);
        vm.expectEmit();
        emit EventsLib.CreateVaultV2(expectedVaultAddress, _asset);
        IVaultV2 vault = IVaultV2(vaultFactory.createVaultV2(_owner, _asset, _salt));
        assertEq(address(vault), expectedVaultAddress);
        assertTrue(vaultFactory.isVaultV2(address(vault)));
        assertEq(vault.owner(), _owner);
        assertEq(vault.asset(), _asset);
    }

    function testVaultV2ConstructorEvent(address _owner, address _asset, bytes32 _salt) public {
        vm.expectEmit();
        emit EventsLib.SetOwner(_owner);
        vaultFactory.createVaultV2(_owner, _asset, _salt);
    }

    function testCreateManualInterestController(address owner, bytes32 salt) public {
        ManualInterestControllerFactory manualInterestControllerFactory = new ManualInterestControllerFactory();

        bytes32 initCodeHash =
            keccak256(abi.encodePacked(type(ManualInterestController).creationCode, abi.encode(owner)));
        address expectedAddress = vm.computeCreate2Address(salt, initCodeHash, address(manualInterestControllerFactory));
        vm.expectEmit();
        emit ManualInterestControllerFactory.CreateManualInterestController(expectedAddress, owner);
        IInterestController manualInterestController =
            IInterestController(manualInterestControllerFactory.createManualInterestController(owner, salt));
        assertEq(address(manualInterestController), expectedAddress);
        assertTrue(manualInterestControllerFactory.isManualInterestController(address(manualInterestController)));
        assertEq(ManualInterestController(address(manualInterestController)).owner(), owner);
    }
}
