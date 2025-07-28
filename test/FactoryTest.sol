// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Morpho Association
pragma solidity ^0.8.0;

import "./BaseTest.sol";

contract FactoryTest is BaseTest {
    function testCreateVaultV2(address _owner, address asset, bytes32 salt) public {
        vm.assume(asset != address(vm));
        vm.mockCall(asset, IERC20.decimals.selector, abi.encode(uint8(18)));
        bytes32 initCodeHash = keccak256(abi.encodePacked(vm.getCode("VaultV2"), abi.encode(_owner, asset)));
        address expectedVaultAddress = address(
            uint160(uint256(keccak256(abi.encodePacked(uint8(0xff), address(vaultFactory), salt, initCodeHash))))
        );
        vm.expectEmit();
        emit IVaultV2Factory.CreateVaultV2(_owner, asset, salt, expectedVaultAddress);
        address newVault = address(IVaultV2(vaultFactory.createVaultV2(_owner, asset, salt)));
        assertEq(newVault, expectedVaultAddress);
        assertTrue(vaultFactory.isVaultV2(newVault));
        assertEq(vaultFactory.vaultV2(_owner, asset, salt), newVault);
    }
}
