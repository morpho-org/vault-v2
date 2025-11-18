// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Morpho Association
pragma solidity 0.8.28;

import {MorphoMarketV1AdapterV2} from "./MorphoMarketV1AdapterV2.sol";
import {IMorphoMarketV1AdapterV2Factory} from "./interfaces/IMorphoMarketV1AdapterV2Factory.sol";
import {MarketParams, Id} from "../../lib/morpho-blue/src/interfaces/IMorpho.sol";
import {MarketParamsLib} from "../../lib/morpho-blue/src/libraries/MarketParamsLib.sol";

contract MorphoMarketV1AdapterV2Factory is IMorphoMarketV1AdapterV2Factory {
    using MarketParamsLib for MarketParams;
    /* STORAGE */

    mapping(address parentVault => mapping(address morpho => mapping(Id marketParamsId => address))) public
        morphoMarketV1AdapterV2;
    mapping(address account => bool) public isMorphoMarketV1AdapterV2;

    /* FUNCTIONS */

    function createMorphoMarketV1AdapterV2(address parentVault, address morpho, MarketParams memory marketParams)
        external
        returns (address)
    {
        address _morphoMarketV1AdapterV2 =
            address(new MorphoMarketV1AdapterV2{salt: bytes32(0)}(parentVault, morpho, marketParams));
        morphoMarketV1AdapterV2[parentVault][morpho][marketParams.id()] = _morphoMarketV1AdapterV2;
        isMorphoMarketV1AdapterV2[_morphoMarketV1AdapterV2] = true;
        emit CreateMorphoMarketV1AdapterV2(parentVault, morpho, marketParams, _morphoMarketV1AdapterV2);
        return _morphoMarketV1AdapterV2;
    }
}
