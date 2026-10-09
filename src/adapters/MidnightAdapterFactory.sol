// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Morpho Association
pragma solidity 0.8.37;

import {MidnightAdapter} from "./MidnightAdapter.sol";
import {IMidnightAdapterFactory} from "./interfaces/IMidnightAdapterFactory.sol";

contract MidnightAdapterFactory is IMidnightAdapterFactory {
    bytes32 private constant CREATE_MIDNIGHT_ADAPTER_EVENT_SIGNATURE =
        0x0905e98509183cd5c4924773be2ae01631be2473c0e305a506ee61df1dc02b96;

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
        assembly ("memory-safe") {
            mstore(0, sload(durations.slot))
            return(0, 32)
        }
    }

    /* FUNCTIONS */

    function createMidnightAdapter(address parentVault, bytes32 salt) external returns (address) {
        address _midnightAdapter = address(new MidnightAdapter{salt: salt}(parentVault, midnight, durations));
        midnightAdapter[parentVault][salt] = _midnightAdapter;
        isMidnightAdapter[_midnightAdapter] = true;
        assembly ("memory-safe") {
            mstore(0, salt)
            log3(0, 32, CREATE_MIDNIGHT_ADAPTER_EVENT_SIGNATURE, parentVault, _midnightAdapter)
        }
        return _midnightAdapter;
    }
}
