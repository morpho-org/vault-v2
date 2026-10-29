// SPDX-License-Identifier: MIT
// Copyright (c) 2025 Morpho Association
pragma solidity 0.8.37;

import {MidnightAdapter} from "./MidnightAdapter.sol";
import {IMidnightAdapterFactory} from "./interfaces/IMidnightAdapterFactory.sol";
import {IVaultV2CompatibleEnterGateFactory} from "../periphery/gates/interfaces/IVaultV2CompatibleEnterGateFactory.sol";

contract MidnightAdapterFactory is IMidnightAdapterFactory {
    /* IMMUTABLES */

    address public immutable midnight;
    address public immutable enterGateFactory;

    /* STORAGE */

    /// @dev durationsHash is keccak256(abi.encode(durations)).
    mapping(address parentVault => mapping(bytes32 durationsHash => mapping(bytes32 salt => address))) public
        midnightAdapter;
    mapping(address account => bool) public isCreated;

    /* CONSTRUCTOR */

    /// @dev The enter gate factory must use the same Midnight because its gates check that Midnight's liquidation lock.
    constructor(address _midnight, address _enterGateFactory) {
        require(
            _enterGateFactory == address(0)
                || IVaultV2CompatibleEnterGateFactory(_enterGateFactory).midnight() == _midnight,
            EnterGateFactoryMidnightMismatch()
        );
        midnight = _midnight;
        enterGateFactory = _enterGateFactory;
        emit CreateMidnightAdapterFactory(_midnight, enterGateFactory);
    }

    /* FUNCTIONS */

    /// @dev The array of capped durations must be of size <= 8, and strictly increasing. Durations must be > 0 and fit on 32 bits.
    /// @dev Adapters use the factory's enterGateFactory; deploy a factory with address(0) for ungated adapters.
    function createMidnightAdapter(address parentVault, uint256[] memory durations, bytes32 salt)
        external
        returns (address)
    {
        address _midnightAdapter =
            address(new MidnightAdapter{salt: salt}(parentVault, midnight, durations, enterGateFactory));
        midnightAdapter[parentVault][keccak256(abi.encode(durations))][salt] = _midnightAdapter;
        isCreated[_midnightAdapter] = true;
        emit CreateMidnightAdapter(parentVault, durations, salt, _midnightAdapter);
        return _midnightAdapter;
    }
}
