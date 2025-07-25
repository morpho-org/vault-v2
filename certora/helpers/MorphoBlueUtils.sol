// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Morpho Association
pragma solidity 0.8.28;

import {MarketParams, Id} from "../../lib/morpho-blue/src/interfaces/IMorpho.sol";
import "../../lib/morpho-blue/src/libraries/MarketParamsLib.sol";

contract MorphoBlueUtils {
    using MarketParamsLib for MarketParams;

    function marketParamsToBytes(MarketParams memory marketParams) external pure returns(bytes memory) {
        return abi.encode(marketParams);
    }

    function id(MarketParams memory marketParams) external pure returns(Id) {
        return marketParams.id();
    }

}
