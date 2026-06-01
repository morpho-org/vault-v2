// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Morpho Association
pragma solidity 0.8.34;

import {MidnightAdapter} from "./MidnightAdapter.sol";
import {IMidnightAdapterFactory} from "./interfaces/IMidnightAdapterFactory.sol";

contract MidnightAdapterFactory is IMidnightAdapterFactory {
    /* STORAGE */

    mapping(address parentVault => mapping(address midnight => address)) public midnightAdapter;
    mapping(address account => bool) public isMidnightAdapter;
    uint256[] public durations;

    /* CONSTRUCTOR */

    constructor(uint256[] memory _durations) {
        durations = _durations;
    }

    /* GETTERS */

    function durationsLength() external view returns (uint256) {
        return durations.length;
    }

    /* FUNCTIONS */

    function createMidnightAdapter(address parentVault, address midnight) external returns (address) {
        address _midnightAdapter = address(new MidnightAdapter{salt: bytes32(0)}(parentVault, midnight, durations));
        midnightAdapter[parentVault][midnight] = _midnightAdapter;
        isMidnightAdapter[_midnightAdapter] = true;
        emit CreateMidnightAdapter(parentVault, midnight, _midnightAdapter);
        return _midnightAdapter;
    }
}
