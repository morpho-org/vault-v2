// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Morpho Association
pragma solidity 0.8.34;

import {MidnightAdapter} from "./MidnightAdapter.sol";
import {IMidnightAdapterFactory} from "./interfaces/IMidnightAdapterFactory.sol";

contract MidnightAdapterFactory is IMidnightAdapterFactory {
    /* IMMUTABLES */

    address public immutable midnight;
    address public immutable enterGateFactory;

    /* STORAGE */

    mapping(address parentVault => mapping(bool useGateFactory => mapping(bytes32 salt => address))) public
        midnightAdapter;
    mapping(address account => bool) public isMidnightAdapter;
    uint256[] public durations;

    /* CONSTRUCTOR */

    /// @dev Durations are checked only when an adapter is created.
    constructor(address _midnight, uint256[] memory _durations, address _enterGateFactory) {
        midnight = _midnight;
        enterGateFactory = _enterGateFactory;
        durations = _durations;
        emit CreateMidnightAdapterFactory(_midnight, _durations, _enterGateFactory);
    }

    /* GETTERS */

    function durationsLength() external view returns (uint256) {
        return durations.length;
    }

    /* FUNCTIONS */

    function createMidnightAdapter(address parentVault, bool useGateFactory, bytes32 salt) external returns (address) {
        address _enterGateFactory = useGateFactory ? enterGateFactory : address(0);
        address _midnightAdapter = address(
            new MidnightAdapter{salt: keccak256(abi.encode(useGateFactory, salt))}(
                parentVault, midnight, durations, _enterGateFactory
            )
        );
        midnightAdapter[parentVault][useGateFactory][salt] = _midnightAdapter;
        isMidnightAdapter[_midnightAdapter] = true;
        emit CreateMidnightAdapter(parentVault, _midnightAdapter, useGateFactory, salt);
        return _midnightAdapter;
    }
}
