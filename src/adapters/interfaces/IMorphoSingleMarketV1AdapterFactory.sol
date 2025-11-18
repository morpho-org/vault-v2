// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Morpho Association
pragma solidity >=0.5.0;

import {MarketParams, Id} from "../../../lib/morpho-blue/src/interfaces/IMorpho.sol";

interface IMorphoSingleMarketV1AdapterFactory {
    /* EVENTS */

    event CreateMorphoSingleMarketV1Adapter(
        address indexed parentVault,
        address indexed morpho,
        MarketParams marketParams,
        address indexed morphoSingleMarketV1Adapter
    );

    /* FUNCTIONS */

    function morphoSingleMarketV1Adapter(address parentVault, address morpho, Id marketParamsId)
        external
        view
        returns (address);
    function isMorphoSingleMarketV1Adapter(address account) external view returns (bool);
    function createMorphoSingleMarketV1Adapter(address parentVault, address morpho, MarketParams memory marketParams)
        external
        returns (address morphoSingleMarketV1Adapter);
}
