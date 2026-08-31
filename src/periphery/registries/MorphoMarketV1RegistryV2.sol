// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Morpho Association
pragma solidity 0.8.28;

import {IMorphoMarketV1AdapterV2Factory} from "../../adapters/interfaces/IMorphoMarketV1AdapterV2Factory.sol";
import {IMorphoMarketV1RegistryV2} from "./interfaces/IMorphoMarketV1RegistryV2.sol";

contract MorphoMarketV1RegistryV2 is IMorphoMarketV1RegistryV2 {
    address public immutable morphoMarketV1AdapterV2Factory;

    constructor(address _morphoMarketV1AdapterV2Factory) {
        morphoMarketV1AdapterV2Factory = _morphoMarketV1AdapterV2Factory;
    }

    function isInRegistry(address adapter) external view returns (bool) {
        return IMorphoMarketV1AdapterV2Factory(morphoMarketV1AdapterV2Factory).isMorphoMarketV1AdapterV2(adapter);
    }
}
