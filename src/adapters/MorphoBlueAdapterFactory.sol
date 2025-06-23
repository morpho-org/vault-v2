// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Morpho Association
pragma solidity 0.8.28;

import {MorphoBlueAdapter} from "./MorphoBlueAdapter.sol";
import {IMorphoBlueAdapterFactory} from "./interfaces/IMorphoBlueAdapterFactory.sol";

contract MorphoBlueAdapterFactory is IMorphoBlueAdapterFactory {
    /* STORAGE */

    mapping(address parentVault => mapping(address morpho => address)) public morphoBlueAdapter;
    mapping(address account => bool) public isMorphoBlueAdapter;

    /* FUNCTIONS */

    function createMorphoBlueAdapter(address parentVault, address morpho) external returns (address) {
        address _morphoBlueAdapter = address(new MorphoBlueAdapter{salt: bytes32(0)}(parentVault, morpho));
        morphoBlueAdapter[parentVault][morpho] = _morphoBlueAdapter;
        isMorphoBlueAdapter[_morphoBlueAdapter] = true;
        emit CreateMorphoBlueAdapter(parentVault, _morphoBlueAdapter);
        return _morphoBlueAdapter;
    }
}
