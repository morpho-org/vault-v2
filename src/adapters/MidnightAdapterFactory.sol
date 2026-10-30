// SPDX-License-Identifier: MIT
// Copyright (c) 2025 Morpho Association
pragma solidity 0.8.37;

import {MidnightAdapter} from "./MidnightAdapter.sol";
import {IMidnightAdapterFactory} from "./interfaces/IMidnightAdapterFactory.sol";

contract MidnightAdapterFactory is IMidnightAdapterFactory {
    /* IMMUTABLES */

    address public immutable midnight;

    /* STORAGE */

    /// @dev durationsHash is keccak256(abi.encode(durations)).
    /// The index counts adapters created with the same parentVault and durations, starting at 0.
    mapping(address parentVault => mapping(bytes32 durationsHash => mapping(uint256 index => address))) public
        midnightAdapter;
    mapping(address parentVault => mapping(bytes32 durationsHash => uint256)) public midnightAdapterCount;
    mapping(address account => bool) public isMidnightAdapter;

    /* CONSTRUCTOR */

    constructor(address _midnight) {
        midnight = _midnight;
        emit CreateMidnightAdapterFactory(_midnight);
    }

    /* FUNCTIONS */

    /// @dev The array of capped durations must be of size <= 8, and strictly increasing. Durations must be > 0 and fit on 32 bits.
    function createMidnightAdapter(address parentVault, uint256[] memory durations) external returns (address) {
        bytes32 durationsHash = keccak256(abi.encode(durations));
        uint256 index = midnightAdapterCount[parentVault][durationsHash]++;
        address _midnightAdapter = address(new MidnightAdapter(parentVault, midnight, durations));
        midnightAdapter[parentVault][durationsHash][index] = _midnightAdapter;
        isMidnightAdapter[_midnightAdapter] = true;
        emit CreateMidnightAdapter(parentVault, durations, index, _midnightAdapter);
        return _midnightAdapter;
    }
}
