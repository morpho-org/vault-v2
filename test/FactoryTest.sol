// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Morpho Association
pragma solidity ^0.8.0;

import "./BaseTest.sol";
import {VaultV2AddressLib} from "../src/libraries/periphery/VaultV2AddressLib.sol";

contract FactoryTest is BaseTest {
    function testCreateVaultV2(address _owner, address asset, bytes32 salt) public {
        vm.assume(asset != address(vm));
        vm.mockCall(asset, IERC20.decimals.selector, abi.encode(uint8(18)));
        bytes32 initCodeHash = keccak256(abi.encodePacked(vm.getCode("VaultV2"), abi.encode(_owner, asset)));
        address expectedVaultAddress = address(
            uint160(uint256(keccak256(abi.encodePacked(uint8(0xff), address(vaultFactory), salt, initCodeHash))))
        );
        vm.expectEmit();
        emit IVaultV2Factory.CreateVaultV2(_owner, asset, expectedVaultAddress);
        IVaultV2 newVault = IVaultV2(vaultFactory.createVaultV2(_owner, asset, salt));
        assertEq(address(newVault), expectedVaultAddress);
        assertTrue(vaultFactory.isVaultV2(address(newVault)));
    }

    function testVaultV2AddressLib(address _owner, address asset, bytes32 salt) public {
        vm.assume(asset != address(vm));
        if (keccak256(vm.getCode("VaultV2")) != keccak256(type(VaultV2).creationCode)) vm.skip(true);
        vm.mockCall(asset, IERC20.decimals.selector, abi.encode(uint8(18)));
        assertEq(
            VaultV2AddressLib.computeVaultV2Address(address(vaultFactory), _owner, asset, salt),
            vaultFactory.createVaultV2(_owner, asset, salt)
        );
    }
}
