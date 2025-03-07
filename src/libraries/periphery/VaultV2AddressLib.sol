// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import {VaultV2} from "../../VaultV2.sol";

library VaultV2AddressLib {
    function computeVaultV2Address(
        address factory,
        address owner,
        address curator,
        address allocator,
        address asset,
        string memory name,
        string memory symbol
    ) internal pure returns (address) {
        bytes32 initCodeHash = keccak256(
            abi.encodePacked(
                type(VaultV2).creationCode, abi.encode(factory, owner, curator, allocator, asset, name, symbol)
            )
        );
        return address(uint160(uint256(keccak256(abi.encodePacked(uint8(0xff), factory, uint256(0), initCodeHash)))));
    }
}
