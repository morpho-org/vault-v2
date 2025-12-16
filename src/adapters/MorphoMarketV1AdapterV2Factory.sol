// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Morpho Association
pragma solidity 0.8.28;

import {MorphoMarketV1AdapterV2} from "./MorphoMarketV1AdapterV2.sol";
import {IMorphoMarketV1AdapterV2Factory} from "./interfaces/IMorphoMarketV1AdapterV2Factory.sol";

/// @dev irm must be the adaptive curve irm.
contract MorphoMarketV1AdapterV2Factory is IMorphoMarketV1AdapterV2Factory {
    /* IMMUTABLES */

    address public immutable morpho;
    address public immutable adaptiveCurveIrm;

    /* STORAGE */

    mapping(address parentVault => address) public morphoMarketV1AdapterV2;
    mapping(address account => bool) public isMorphoMarketV1AdapterV2;

    /* CONSTRUCTOR */

    constructor(address _morpho, address _adaptiveCurveIrm) {
        morpho = _morpho;
        adaptiveCurveIrm = _adaptiveCurveIrm;
        emit CreateMorphoMarketV1AdapterV2Factory(morpho, adaptiveCurveIrm);
    }

    /* FUNCTIONS */

    function createMorphoMarketV1AdapterV2(address parentVault) external returns (address) {
        address _morphoMarketV1AdapterV2 =
            address(new MorphoMarketV1AdapterV2{salt: bytes32(0)}(parentVault, morpho, adaptiveCurveIrm));
        morphoMarketV1AdapterV2[parentVault] = _morphoMarketV1AdapterV2;
        isMorphoMarketV1AdapterV2[_morphoMarketV1AdapterV2] = true;
        emit CreateMorphoMarketV1AdapterV2(parentVault, _morphoMarketV1AdapterV2);
        return _morphoMarketV1AdapterV2;
    }
}
