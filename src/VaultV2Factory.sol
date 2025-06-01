// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.28;

import {EventsLib} from "./libraries/EventsLib.sol";

import {VaultV2} from "./VaultV2.sol";
import {IVaultV2Factory} from "./interfaces/IVaultV2Factory.sol";

contract VaultV2Factory is IVaultV2Factory {
    mapping(address account => bool) public isVaultV2;

    /// @dev Returns the address of the deployed VaultV2.
    function createVaultV2(address owner, address asset, string memory symbol, string memory name, bytes32 salt)
        external
        returns (address)
    {
        address vaultV2 = address(new VaultV2{salt: salt}(owner, asset, name, symbol));

        isVaultV2[vaultV2] = true;
        emit EventsLib.CreateVaultV2(owner, asset, vaultV2, name, symbol);

        return vaultV2;
    }
}
