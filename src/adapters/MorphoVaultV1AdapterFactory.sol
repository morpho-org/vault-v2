// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Morpho Association
pragma solidity 0.8.28;

import {MorphoVaultV1Adapter} from "./MorphoVaultV1Adapter.sol";
import {IMorphoVaultV1AdapterFactory} from "./interfaces/IMorphoVaultV1AdapterFactory.sol";

contract MorphoVaultV1AdapterFactory is IMorphoVaultV1AdapterFactory {
    /* STORAGE */

    mapping(address parentVault => mapping(address morphoVaultV1 => address)) public morphoVaultV1Adapter;
    mapping(address account => bool) public isMorphoVaultV1Adapter;

    /* FUNCTIONS */

    /// @dev Returns the address of the deployed MorphoVaultV1Adapter.
    function createMorphoVaultV1Adapter(address parentVault, address morphoVaultV1) external returns (address) {
        address _morphoVaultV1Adapter = address(new MorphoVaultV1Adapter{salt: bytes32(0)}(parentVault, morphoVaultV1));
        morphoVaultV1Adapter[parentVault][morphoVaultV1] = _morphoVaultV1Adapter;
        isMorphoVaultV1Adapter[_morphoVaultV1Adapter] = true;
        emit CreateMorphoVaultV1Adapter(parentVault, morphoVaultV1, _morphoVaultV1Adapter);
        return _morphoVaultV1Adapter;
    }
}
