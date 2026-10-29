// SPDX-License-Identifier: MIT
// Copyright (c) 2025 Morpho Association
pragma solidity 0.8.37;

import {MidnightAdapter} from "./MidnightAdapter.sol";
import {IMidnightAdapterFactory} from "./interfaces/IMidnightAdapterFactory.sol";
import {IVaultV2CompatibleEnterGateFactory} from "../periphery/gates/interfaces/IVaultV2CompatibleEnterGateFactory.sol";

contract MidnightAdapterFactory is IMidnightAdapterFactory {
    /* IMMUTABLES */

    address public immutable midnight;

    /* STORAGE */

    /// @dev durationsHash is keccak256(abi.encode(durations)).
    mapping(
        address parentVault
            => mapping(bytes32 durationsHash => mapping(address enterGateFactory => mapping(bytes32 salt => address)))
    ) public midnightAdapter;
    mapping(address account => bool) public isCreated;

    /* CONSTRUCTOR */

    constructor(address _midnight) {
        midnight = _midnight;
        emit CreateMidnightAdapterFactory(_midnight);
    }

    /* FUNCTIONS */

    /// @dev The array of capped durations must be of size <= 8, and strictly increasing. Durations must be > 0 and fit on 32 bits.
    /// @dev enterGateFactory is address(0) for ungated adapters; otherwise see the ENTER GATE requirements in MidnightAdapter.
    function createMidnightAdapter(
        address parentVault,
        uint256[] memory durations,
        address enterGateFactory,
        bytes32 salt
    ) external returns (address) {
        require(
            enterGateFactory == address(0)
                || IVaultV2CompatibleEnterGateFactory(enterGateFactory).midnight() == midnight,
            EnterGateFactoryMidnightMismatch()
        );
        address _midnightAdapter =
            address(new MidnightAdapter{salt: salt}(parentVault, midnight, durations, enterGateFactory));
        midnightAdapter[parentVault][keccak256(abi.encode(durations))][enterGateFactory][salt] = _midnightAdapter;
        isCreated[_midnightAdapter] = true;
        emit CreateMidnightAdapter(parentVault, durations, salt, _midnightAdapter, enterGateFactory);
        return _midnightAdapter;
    }
}
