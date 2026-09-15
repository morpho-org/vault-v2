// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Morpho Association
pragma solidity 0.8.34;

import {MidnightAdapter} from "./MidnightAdapter.sol";
import {IMidnightAdapterFactory} from "./interfaces/IMidnightAdapterFactory.sol";

contract MidnightAdapterFactory is IMidnightAdapterFactory {
    /* STORAGE */

    mapping(address parentVault => mapping(address midnight => mapping(bytes32 durationsHash => address))) private
        _midnightAdapters;
    mapping(address account => bool) public isMidnightAdapter;

    /* GETTERS */

    function midnightAdapter(address parentVault, address midnight, uint256[] calldata durations)
        external
        view
        returns (address)
    {
        return _midnightAdapters[parentVault][midnight][keccak256(abi.encode(durations))];
    }

    /* FUNCTIONS */

    function createMidnightAdapter(address parentVault, address midnight, uint256[] calldata durations)
        external
        returns (address)
    {
        address _midnightAdapter = address(new MidnightAdapter{salt: bytes32(0)}(parentVault, midnight, durations));
        _midnightAdapters[parentVault][midnight][keccak256(abi.encode(durations))] = _midnightAdapter;
        isMidnightAdapter[_midnightAdapter] = true;
        emit CreateMidnightAdapter(parentVault, midnight, durations, _midnightAdapter);
        return _midnightAdapter;
    }
}
