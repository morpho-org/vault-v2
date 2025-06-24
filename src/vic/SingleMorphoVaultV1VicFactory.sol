// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Morpho Association
pragma solidity 0.8.28;

import {ISingleMorphoVaultV1VicFactory} from "./interfaces/ISingleMorphoVaultV1VicFactory.sol";

import {SingleMorphoVaultV1Vic} from "./SingleMorphoVaultV1Vic.sol";

contract SingleMorphoVaultV1VicFactory is ISingleMorphoVaultV1VicFactory {
    /* STORAGE */

    mapping(address parentVault => mapping(address morphoVaultV1Adapter => address)) public singleMorphoVaultV1Vic;
    mapping(address account => bool) public isSingleMorphoVaultV1Vic;

    /* FUNCTIONS */

    /// @dev Returns the address of the deployed SingleMorphoVaultV1Vic.
    function createSingleMorphoVaultV1Vic(address parentVault, address morphoVaultV1Adapter)
        external
        returns (address)
    {
        address vic = address(new SingleMorphoVaultV1Vic{salt: bytes32(0)}(parentVault, morphoVaultV1Adapter));

        isSingleMorphoVaultV1Vic[vic] = true;
        singleMorphoVaultV1Vic[parentVault][morphoVaultV1Adapter] = vic;
        emit CreateSingleMorphoVaultV1Vic(vic, parentVault, morphoVaultV1Adapter);

        return vic;
    }
}
