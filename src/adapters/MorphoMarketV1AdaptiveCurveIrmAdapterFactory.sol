// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Morpho Association
pragma solidity 0.8.28;

import {MorphoMarketV1AdaptiveCurveIrmAdapter} from "./MorphoMarketV1AdaptiveCurveIrmAdapter.sol";
import {IMorphoMarketV1AdaptiveCurveIrmAdapterFactory} from
    "./interfaces/IMorphoMarketV1AdaptiveCurveIrmAdapterFactory.sol";

contract MorphoMarketV1AdaptiveCurveIrmAdapterFactory is IMorphoMarketV1AdaptiveCurveIrmAdapterFactory {
    /* STORAGE */

    mapping(address parentVault => mapping(address morpho => address)) public morphoMarketV1AdaptiveCurveIrmAdapter;
    mapping(address account => bool) public isMorphoMarketV1AdaptiveCurveIrmAdapter;

    /* FUNCTIONS */

    function createMorphoMarketV1AdaptiveCurveIrmAdapter(address parentVault, address morpho, address irm)
        external
        returns (address)
    {
        address _morphoMarketV1AdaptiveCurveIrmAdapter =
            address(new MorphoMarketV1AdaptiveCurveIrmAdapter{salt: bytes32(0)}(parentVault, morpho, irm));
        morphoMarketV1AdaptiveCurveIrmAdapter[parentVault][morpho] = _morphoMarketV1AdaptiveCurveIrmAdapter;
        isMorphoMarketV1AdaptiveCurveIrmAdapter[_morphoMarketV1AdaptiveCurveIrmAdapter] = true;
        emit CreateMorphoMarketV1AdaptiveCurveIrmAdapter(parentVault, _morphoMarketV1AdaptiveCurveIrmAdapter);
        return _morphoMarketV1AdaptiveCurveIrmAdapter;
    }
}
