// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.28;

import {MorphoBlueAdapter} from "./MorphoBlueAdapter.sol";
import {IMorphoBlueAdapterFactory} from "./interfaces/IMorphoBlueAdapterFactory.sol";
import {MarketParams, Id} from "../../lib/morpho-blue/src/interfaces/IMorpho.sol";
import {MarketParamsLib} from "../../lib/morpho-blue/src/libraries/MarketParamsLib.sol";

contract MorphoBlueAdapterFactory is IMorphoBlueAdapterFactory {
    using MarketParamsLib for MarketParams;

    /* IMMUTABLES */

    address public immutable morpho;

    /* STORAGE */

    /// @dev vault => marketId => adapter
    mapping(address => mapping(Id => address)) public _morphoBlueAdapter;
    mapping(address => bool) public isAdapter;

    /* FUNCTIONS */

    constructor(address _morpho) {
        morpho = _morpho;
    }

    function createMorphoBlueAdapter(address vault, MarketParams calldata marketParams) external returns (address) {
        address adapter = address(new MorphoBlueAdapter{salt: bytes32(0)}(vault, morpho, marketParams));
        _morphoBlueAdapter[vault][marketParams.id()] = adapter;
        isAdapter[adapter] = true;
        emit CreateMorphoBlueAdapter(vault, adapter, marketParams);
        return adapter;
    }

    function morphoBlueAdapter(address vault, MarketParams calldata marketParams) external view returns (address) {
        return _morphoBlueAdapter[vault][marketParams.id()];
    }
}
