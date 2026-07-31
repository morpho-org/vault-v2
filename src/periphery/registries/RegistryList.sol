// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Morpho Association
pragma solidity 0.8.28;

import {IRegistryList} from "./interfaces/IRegistryList.sol";
import {IAdapterRegistry} from "../../interfaces/IAdapterRegistry.sol";

contract RegistryList is IRegistryList {
    address public owner;

    /// @dev Owner controlled append-only list of registries.
    /// @dev This registry is effectively "add-only" only if all sub-registries are also "add-only".
    address[] public subRegistries;

    event Constructor(address indexed owner);
    event SetOwner(address indexed newOwner);
    event AddSubRegistry(address indexed subRegistry);

    function subRegistriesLength() external view returns (uint256) {
        return subRegistries.length;
    }

    constructor() {
        owner = msg.sender;
        emit Constructor(msg.sender);
    }

    function setOwner(address newOwner) external {
        require(msg.sender == owner, "Not owner");
        owner = newOwner;
        emit SetOwner(newOwner);
    }

    /// @dev Adding a subRegistry that reverts or makes looping too gas consuming will make new registries uneffective
    /// (vaults will not be able to validate adapters that would be validated by registries that have been added after).
    function addSubRegistry(address subRegistry) external {
        require(msg.sender == owner, "Not owner");
        subRegistries.push(subRegistry);
        emit AddSubRegistry(subRegistry);
    }

    function isInRegistry(address adapter) public view returns (bool) {
        for (uint256 i = 0; i < subRegistries.length; i++) {
            if (IAdapterRegistry(subRegistries[i]).isInRegistry(adapter)) return true;
        }
        return false;
    }
}
