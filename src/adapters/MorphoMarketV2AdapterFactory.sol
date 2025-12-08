// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Morpho Association
pragma solidity 0.8.28;

import {MorphoMarketV2Adapter} from "./MorphoMarketV2Adapter.sol";
import {IMorphoMarketV2AdapterFactory} from "./interfaces/IMorphoMarketV2AdapterFactory.sol";

contract MorphoMarketV2AdapterFactory is IMorphoMarketV2AdapterFactory {
    /* STORAGE */

    mapping(address parentVault => mapping(address morpho => address)) public morphoMarketV2Adapter;
    mapping(address account => bool) public isMorphoMarketV2Adapter;

    /* FUNCTIONS */

    function createMorphoMarketV2Adapter(address parentVault, address morpho) external returns (address) {
        address _morphoMarketV2Adapter =
            address(new MorphoMarketV2Adapter{salt: bytes32(0)}(parentVault, morpho, durations()));
        morphoMarketV2Adapter[parentVault][morpho] = _morphoMarketV2Adapter;
        isMorphoMarketV2Adapter[_morphoMarketV2Adapter] = true;
        emit CreateMorphoMarketV2Adapter(parentVault, morpho, _morphoMarketV2Adapter);
        return _morphoMarketV2Adapter;
    }

    function durations() public pure returns (uint256[] memory) {
        uint256[] memory _durations = new uint256[](5);
        _durations[0] = 1 days;
        _durations[1] = 7 days;
        _durations[2] = 30 days;
        _durations[3] = 90 days;
        _durations[4] = 180 days;
        return _durations;
    }
}
