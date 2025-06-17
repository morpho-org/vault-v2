// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Morpho Association
pragma solidity 0.8.28;

import {MorphoBlueAdapter} from "./MorphoBlueAdapter.sol";
import {IMorphoBlueAdapterFactory} from "./interfaces/IMorphoBlueAdapterFactory.sol";

contract MorphoBlueAdapterFactory is IMorphoBlueAdapterFactory {
    /* STORAGE */

    mapping(address parentVault => mapping(address morpho => mapping(address irm => address))) public morphoBlueAdapter;
    mapping(address account => bool) public isMorphoBlueAdapter;

    /* FUNCTIONS */

    function createMorphoBlueAdapter(address parentVault, address morpho, address irm) external returns (address) {
        address _morphoBlueAdapter = address(new MorphoBlueAdapter{salt: bytes32(0)}(parentVault, morpho, irm));
        morphoBlueAdapter[parentVault][morpho][irm] = _morphoBlueAdapter;
        isMorphoBlueAdapter[_morphoBlueAdapter] = true;
        emit CreateMorphoBlueAdapter(parentVault, _morphoBlueAdapter);
        return _morphoBlueAdapter;
    }
}
