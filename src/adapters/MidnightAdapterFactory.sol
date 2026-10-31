// SPDX-License-Identifier: MIT
// Copyright (c) 2025 Morpho Association
pragma solidity 0.8.37;

import {MidnightAdapter} from "./MidnightAdapter.sol";
import {IMidnightAdapterFactory} from "./interfaces/IMidnightAdapterFactory.sol";
import {IVaultV2Factory} from "../interfaces/IVaultV2Factory.sol";

contract MidnightAdapterFactory is IMidnightAdapterFactory {
    /* IMMUTABLES */

    address public immutable midnight;
    address public immutable vaultV2Factory;

    /* STORAGE */

    /// @dev durationsHash is keccak256(abi.encode(durations)).
    mapping(address parentVault => mapping(bytes32 durationsHash => mapping(bytes32 salt => address))) public
        midnightAdapter;
    mapping(address account => bool) public isMidnightAdapter;

    /* CONSTRUCTOR */

    constructor(address _midnight, address _vaultV2Factory) {
        midnight = _midnight;
        vaultV2Factory = _vaultV2Factory;
        emit CreateMidnightAdapterFactory(_midnight, _vaultV2Factory);
    }

    /* FUNCTIONS */

    /// @dev The array of capped durations must be of size <= 8, and strictly increasing. Durations must be > 0 and fit on 32 bits.
    function createMidnightAdapter(address parentVault, uint256[] memory durations, bytes32 salt)
        external
        returns (address)
    {
        require(IVaultV2Factory(vaultV2Factory).isVaultV2(parentVault), NotVaultV2());
        address _midnightAdapter = address(new MidnightAdapter{salt: salt}(parentVault, midnight, durations));
        midnightAdapter[parentVault][keccak256(abi.encode(durations))][salt] = _midnightAdapter;
        isMidnightAdapter[_midnightAdapter] = true;
        emit CreateMidnightAdapter(parentVault, durations, salt, _midnightAdapter);
        return _midnightAdapter;
    }
}
