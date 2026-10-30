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
    mapping(address parentVault => mapping(bytes32 durationsHash => mapping(bytes32 salt => address))) public
        midnightAdapter;
    mapping(address account => bool) public isMidnightAdapter;

    /* CONSTRUCTOR */

    constructor(address _midnight) {
        midnight = _midnight;
        emit CreateMidnightAdapterFactory(_midnight);
    }

    /* FUNCTIONS */

    /// @dev The array of capped durations must be of size <= 8, and strictly increasing. Durations must be > 0 and fit on 32 bits.
    /// @dev The salt is derived from preSalt and msg.sender. Bundles (shared msg.sender) must derive preSalt from the
    /// initiator and a pre-preSalt, otherwise anyone using the bundle can take the address.
    function createMidnightAdapter(address parentVault, uint256[] memory durations, bytes32 preSalt)
        external
        returns (address)
    {
        bytes32 salt = keccak256(abi.encode(preSalt, msg.sender));
        address _midnightAdapter = address(new MidnightAdapter{salt: salt}(parentVault, midnight, durations));
        midnightAdapter[parentVault][keccak256(abi.encode(durations))][salt] = _midnightAdapter;
        isMidnightAdapter[_midnightAdapter] = true;
        emit CreateMidnightAdapter(msg.sender, parentVault, durations, preSalt, _midnightAdapter);
        return _midnightAdapter;
    }
}
