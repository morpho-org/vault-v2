// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity >=0.5.0;

import {IAdapterFactory} from "../../interfaces/IAdapterFactory.sol";
import {MarketParams} from "../../../lib/morpho-blue/src/interfaces/IMorpho.sol";

interface IMorphoBlueAdapterFactory is IAdapterFactory {
    /* EVENTS */

    event CreateMorphoBlueAdapter(address indexed vault, address indexed morphoBlueAdapter, MarketParams marketParams);

    /* FUNCTIONS */

    function createMorphoBlueAdapter(address vault, MarketParams calldata marketParams) external returns (address);
    function morphoBlueAdapter(address vault, MarketParams calldata marketParams) external view returns (address);
    function morpho() external view returns (address);
}
