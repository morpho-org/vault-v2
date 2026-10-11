// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Morpho Association
pragma solidity 0.8.37;

import {MidnightAdapter} from "./MidnightAdapter.sol";
import {IMidnightAdapterFactory} from "./interfaces/IMidnightAdapterFactory.sol";

contract MidnightAdapterFactory is IMidnightAdapterFactory {
    /* IMMUTABLES */

    address public immutable midnight;

    /* STORAGE */

    mapping(address parentVault => mapping(bytes32 salt => address)) public midnightAdapter;
    mapping(address account => bool) public isMidnightAdapter;
    uint256[] public durations;

    /* CONSTRUCTOR */

    /// @dev Durations are checked only when an adapter is created.
    constructor(address _midnight, uint256[] memory _durations) {
        midnight = _midnight;
        durations = _durations;
        emit CreateMidnightAdapterFactory(_midnight, _durations);
    }

    /* GETTERS */

    function durationsLength() external view returns (uint256) {
        return durations.length;
    }

    /* FUNCTIONS */

    function createMidnightAdapter(address parentVault, bytes32 salt) external returns (address) {
        address _midnightAdapter = address(new MidnightAdapter{salt: salt}(parentVault, midnight, durations));
        midnightAdapter[parentVault][salt] = _midnightAdapter;
        isMidnightAdapter[_midnightAdapter] = true;
        emit CreateMidnightAdapter(parentVault, salt, _midnightAdapter);
        return _midnightAdapter;
    }
}
