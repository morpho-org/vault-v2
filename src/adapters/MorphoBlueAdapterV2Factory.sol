// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Morpho Association
pragma solidity 0.8.28;

import {MorphoBlueAdapterV2} from "./MorphoBlueAdapterV2.sol";
import {IMorphoBlueAdapterV2Factory} from "./interfaces/IMorphoBlueAdapterV2Factory.sol";

/// @dev irm must be the adaptive curve irm.
contract MorphoBlueAdapterV2Factory is IMorphoBlueAdapterV2Factory {
    /* IMMUTABLES */

    address public immutable morpho;
    address public immutable adaptiveCurveIrm;

    /* STORAGE */

    mapping(address parentVault => address) public morphoBlueAdapterV2_71Aurmp;
    mapping(address account => bool) public isMorphoBlueAdapterV2_60omp0Z;

    /* CONSTRUCTOR */

    constructor(address _morpho, address _adaptiveCurveIrm) {
        morpho = _morpho;
        adaptiveCurveIrm = _adaptiveCurveIrm;
        emit CreateMorphoMarketV1AdapterV2Factory(morpho, adaptiveCurveIrm);
    }

    /* FUNCTIONS */

    function createMorphoBlueAdapterV2_005kLDJ(address parentVault) external returns (address) {
        address _morphoBlueAdapterV2 =
            address(new MorphoBlueAdapterV2{salt: bytes32(0)}(parentVault, morpho, adaptiveCurveIrm));
        morphoBlueAdapterV2_71Aurmp[parentVault] = _morphoBlueAdapterV2;
        isMorphoBlueAdapterV2_60omp0Z[_morphoBlueAdapterV2] = true;
        emit CreateMorphoMarketV1AdapterV2(parentVault, _morphoBlueAdapterV2);
        return _morphoBlueAdapterV2;
    }
}
