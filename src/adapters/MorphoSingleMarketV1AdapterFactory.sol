// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Morpho Association
pragma solidity 0.8.28;

import {MorphoSingleMarketV1Adapter} from "./MorphoSingleMarketV1Adapter.sol";
import {IMorphoSingleMarketV1AdapterFactory} from "./interfaces/IMorphoSingleMarketV1AdapterFactory.sol";
import {MarketParams, Id} from "../../lib/morpho-blue/src/interfaces/IMorpho.sol";
import {MarketParamsLib} from "../../lib/morpho-blue/src/libraries/MarketParamsLib.sol";

contract MorphoSingleMarketV1AdapterFactory is IMorphoSingleMarketV1AdapterFactory {
    using MarketParamsLib for MarketParams;
    /* STORAGE */

    mapping(address parentVault => mapping(address morpho => mapping(Id marketParamsId => address))) public
        morphoSingleMarketV1Adapter;
    mapping(address account => bool) public isMorphoSingleMarketV1Adapter;

    /* FUNCTIONS */

    function createMorphoSingleMarketV1Adapter(address parentVault, address morpho, MarketParams memory marketParams)
        external
        returns (address)
    {
        address _morphoSingleMarketV1Adapter =
            address(new MorphoSingleMarketV1Adapter{salt: bytes32(0)}(parentVault, morpho, marketParams));
        morphoSingleMarketV1Adapter[parentVault][morpho][marketParams.id()] = _morphoSingleMarketV1Adapter;
        isMorphoSingleMarketV1Adapter[_morphoSingleMarketV1Adapter] = true;
        emit CreateMorphoSingleMarketV1Adapter(parentVault, morpho, marketParams, _morphoSingleMarketV1Adapter);
        return _morphoSingleMarketV1Adapter;
    }
}
