// SPDX-License-Identifier: MIT
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

    /* CONSTRUCTOR */

    constructor(address _midnight) {
        midnight = _midnight;
        emit CreateMidnightAdapterFactory(_midnight);
    }

    /* FUNCTIONS */

    function createMidnightAdapter(address parentVault, bytes32 salt) external returns (address) {
        address _midnightAdapter = address(new MidnightAdapter{salt: salt}(parentVault, midnight));
        midnightAdapter[parentVault][salt] = _midnightAdapter;
        isMidnightAdapter[_midnightAdapter] = true;
        emit CreateMidnightAdapter(parentVault, salt, _midnightAdapter);
        return _midnightAdapter;
    }
}
