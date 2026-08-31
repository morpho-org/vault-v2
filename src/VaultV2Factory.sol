// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Morpho Association
pragma solidity 0.8.28;

import {VaultV2} from "./VaultV2.sol";
import {IVaultV2Factory} from "./interfaces/IVaultV2Factory.sol";

contract VaultV2Factory is IVaultV2Factory {
    mapping(address account => bool) public isVaultV2;
    mapping(address owner => mapping(address asset => mapping(bytes32 salt => address))) public vaultV2;

    /// @dev Returns the address of the deployed VaultV2.
    function createVaultV2(address owner, address asset, bytes32 salt) external returns (address) {
        address newVaultV2 = address(new VaultV2{salt: salt}(owner, asset));

        isVaultV2[newVaultV2] = true;
        vaultV2[owner][asset][salt] = newVaultV2;
        emit CreateVaultV2(owner, asset, salt, newVaultV2);

        return newVaultV2;
    }
}
