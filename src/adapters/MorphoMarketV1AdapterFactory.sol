// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Morpho Association
pragma solidity 0.8.28;

import {MorphoMarketV1Adapter} from "./MorphoMarketV1Adapter.sol";
import {IMorphoMarketV1AdapterFactory} from "./interfaces/IMorphoMarketV1AdapterFactory.sol";

contract MorphoMarketV1AdapterFactory is IMorphoMarketV1AdapterFactory {
    /* STORAGE */

    mapping(address parentVault => mapping(address morpho => address)) public morphoMarketV1Adapter;
    mapping(address account => bool) public isMorphoMarketV1Adapter;

    /* FUNCTIONS */

    function createMorphoMarketV1Adapter(address parentVault, address morpho) external returns (address) {
        address _morphoMarketV1Adapter = address(new MorphoMarketV1Adapter{salt: bytes32(0)}(parentVault, morpho));
        morphoMarketV1Adapter[parentVault][morpho] = _morphoMarketV1Adapter;
        isMorphoMarketV1Adapter[_morphoMarketV1Adapter] = true;
        emit CreateMorphoMarketV1Adapter(parentVault, morpho, _morphoMarketV1Adapter);
        return _morphoMarketV1Adapter;
    }
}
