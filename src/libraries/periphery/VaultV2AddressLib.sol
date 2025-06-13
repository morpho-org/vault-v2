// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Morpho Association
pragma solidity ^0.8.0;

import {VaultV2} from "../../VaultV2.sol";

library VaultV2AddressLib {
    /// @dev Returns the address of the deployed VaultV2.
    function computeVaultV2Address(address factory, address owner, address asset, bytes32 salt)
        internal
        pure
        returns (address)
    {
        bytes32 initCodeHash = keccak256(abi.encodePacked(type(VaultV2).creationCode, abi.encode(owner, asset)));
        return address(uint160(uint256(keccak256(abi.encodePacked(uint8(0xff), factory, salt, initCodeHash)))));
    }
}
