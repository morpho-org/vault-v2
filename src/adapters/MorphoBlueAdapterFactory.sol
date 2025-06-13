// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Morpho Association
pragma solidity 0.8.28;

import {MorphoBlueAdapter} from "./MorphoBlueAdapter.sol";
import {IMorphoBlueAdapterFactory} from "./interfaces/IMorphoBlueAdapterFactory.sol";

contract MorphoBlueAdapterFactory is IMorphoBlueAdapterFactory {
    /* STORAGE */

    mapping(address vault => mapping(address morpho => mapping(address irm => address))) public morphoBlueAdapter;
    mapping(address => bool) public isMorphoBlueAdapter;

    /* FUNCTIONS */

    function createMorphoBlueAdapter(address vault, address morpho, address irm) external returns (address) {
        address _morphoBlueAdapter = address(new MorphoBlueAdapter{salt: bytes32(0)}(vault, morpho, irm));
        morphoBlueAdapter[vault][morpho][irm] = _morphoBlueAdapter;
        isMorphoBlueAdapter[_morphoBlueAdapter] = true;
        emit CreateMorphoBlueAdapter(vault, _morphoBlueAdapter);
        return _morphoBlueAdapter;
    }
}
