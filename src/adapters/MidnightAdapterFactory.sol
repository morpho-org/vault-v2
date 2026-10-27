// SPDX-License-Identifier: MIT
// Copyright (c) 2025 Morpho Association
pragma solidity 0.8.37;

import {MidnightAdapter} from "./MidnightAdapter.sol";
import {IMidnightAdapterFactory} from "./interfaces/IMidnightAdapterFactory.sol";

contract MidnightAdapterFactory is IMidnightAdapterFactory {
    /* IMMUTABLES */

    address public immutable midnight;
    address public immutable enterGateFactory;

    /* STORAGE */

    /// @dev durationsHash is keccak256(abi.encode(durations)).
    mapping(
        address parentVault
            => mapping(bytes32 durationsHash => mapping(bool useGateFactory => mapping(bytes32 salt => address)))
    ) public midnightAdapter;
    mapping(address account => bool) public isCreated;

    /* CONSTRUCTOR */

    constructor(address _midnight, address _enterGateFactory) {
        midnight = _midnight;
        enterGateFactory = _enterGateFactory;
        emit CreateMidnightAdapterFactory(_midnight, enterGateFactory);
    }

    /* FUNCTIONS */

    /// @dev The array of capped durations must be of size <= 8, and strictly increasing. Durations must be > 0 and fit on 32 bits.
    /// @dev With useGateFactory, the adapter enters a gated market only if its gate lets vault users buy through forceDeallocate, which keeps in-kind redemptions possible.
    /// @dev Without useGateFactory, the adapter can enter any gated market, and forceDeallocate there works only with buyers the market's gate allows.
    function createMidnightAdapter(address parentVault, uint256[] memory durations, bool useGateFactory, bytes32 salt)
        external
        returns (address)
    {
        address _enterGateFactory = useGateFactory ? enterGateFactory : address(0);
        address _midnightAdapter =
            address(new MidnightAdapter{salt: salt}(parentVault, midnight, durations, _enterGateFactory));
        midnightAdapter[parentVault][keccak256(abi.encode(durations))][useGateFactory][salt] = _midnightAdapter;
        isCreated[_midnightAdapter] = true;
        emit CreateMidnightAdapter(parentVault, durations, salt, _midnightAdapter, useGateFactory);
        return _midnightAdapter;
    }
}
