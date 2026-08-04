// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Morpho Association
pragma solidity 0.8.28;

import {BlueAdapterV3} from "./BlueAdapterV3.sol";
import {IBlueAdapterV3Factory} from "./interfaces/IBlueAdapterV3Factory.sol";

contract BlueAdapterV3Factory is IBlueAdapterV3Factory {
    /* IMMUTABLES */

    address public immutable morpho;

    /* STORAGE */

    mapping(address parentVault => address) public blueAdapterV3;
    mapping(address account => bool) public isBlueAdapterV3;

    /* CONSTRUCTOR */

    constructor(address _morpho) {
        morpho = _morpho;
        emit CreateBlueAdapterV3Factory(morpho);
    }

    /* FUNCTIONS */

    function createBlueAdapterV3(address parentVault) external returns (address) {
        address _blueAdapterV3 = address(new BlueAdapterV3{salt: bytes32(0)}(parentVault, morpho));
        blueAdapterV3[parentVault] = _blueAdapterV3;
        isBlueAdapterV3[_blueAdapterV3] = true;
        emit CreateBlueAdapterV3(parentVault, _blueAdapterV3);
        return _blueAdapterV3;
    }
}
