// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Morpho Association
pragma solidity >=0.5.0;

import {MarketParams, Id} from "../../../lib/morpho-blue/src/interfaces/IMorpho.sol";

interface IMorphoMarketV1AdapterV2Factory {
    /* EVENTS */

    event CreateMorphoMarketV1AdapterV2(
        address indexed parentVault,
        address indexed morpho,
        MarketParams marketParams,
        address indexed morphoMarketV1AdapterV2
    );

    /* FUNCTIONS */

    function morphoMarketV1AdapterV2(address parentVault, address morpho, Id marketParamsId)
        external
        view
        returns (address);
    function isMorphoMarketV1AdapterV2(address account) external view returns (bool);
    function createMorphoMarketV1AdapterV2(address parentVault, address morpho, MarketParams memory marketParams)
        external
        returns (address morphoMarketV1AdapterV2);
}
