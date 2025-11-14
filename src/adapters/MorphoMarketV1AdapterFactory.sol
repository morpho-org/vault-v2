// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Morpho Association
pragma solidity 0.8.28;

import {MorphoMarketV1Adapter} from "./MorphoMarketV1Adapter.sol";
import {IMorphoMarketV1AdapterFactory} from "./interfaces/IMorphoMarketV1AdapterFactory.sol";
import {MarketParams, Id} from "../../lib/morpho-blue/src/interfaces/IMorpho.sol";
import {MarketParamsLib} from "../../lib/morpho-blue/src/libraries/MarketParamsLib.sol";

contract MorphoMarketV1AdapterFactory is IMorphoMarketV1AdapterFactory {
    using MarketParamsLib for MarketParams;
    /* STORAGE */

    mapping(address parentVault => mapping(address morpho => mapping(Id marketParamsId => address))) public
        morphoMarketV1Adapter;
    mapping(address account => bool) public isMorphoMarketV1Adapter;

    /* FUNCTIONS */

    function createMorphoMarketV1Adapter(address parentVault, address morpho, MarketParams memory marketParams)
        external
        returns (address)
    {
        address _morphoMarketV1Adapter =
            address(new MorphoMarketV1Adapter{salt: bytes32(0)}(parentVault, morpho, marketParams));
        morphoMarketV1Adapter[parentVault][morpho][marketParams.id()] = _morphoMarketV1Adapter;
        isMorphoMarketV1Adapter[_morphoMarketV1Adapter] = true;
        emit CreateMorphoMarketV1Adapter(parentVault, morpho, marketParams, _morphoMarketV1Adapter);
        return _morphoMarketV1Adapter;
    }
}
