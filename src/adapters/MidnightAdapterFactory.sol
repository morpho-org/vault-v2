// SPDX-License-Identifier: MIT
// Copyright (c) 2025 Morpho Association
pragma solidity 0.8.37;

import {MidnightAdapter} from "./MidnightAdapter.sol";
import {IMidnightAdapterFactory} from "./interfaces/IMidnightAdapterFactory.sol";

contract MidnightAdapterFactory is IMidnightAdapterFactory {
    /* IMMUTABLES */

    address public immutable midnight;
    bytes32 public immutable midnightAdapterCreationCodeHash;

    /* STORAGE */

    /// @dev durationsHash is keccak256(abi.encode(durations)).
    mapping(address parentVault => mapping(bytes32 durationsHash => mapping(bytes32 salt => address))) public
        midnightAdapter;
    mapping(address account => bool) public isMidnightAdapter;

    /* CONSTRUCTOR */

    constructor(address _midnight) {
        midnight = _midnight;
        midnightAdapterCreationCodeHash = keccak256(type(MidnightAdapter).creationCode);
        emit CreateMidnightAdapterFactory(_midnight);
    }

    /* FUNCTIONS */

    /// @dev The array of capped durations must be of size <= 8, and strictly increasing. Durations must be > 0 and fit on 32 bits.
    /// @dev creationCode must be the MidnightAdapter creation code (`type(MidnightAdapter).creationCode`), checked against `midnightAdapterCreationCodeHash`.
    function createMidnightAdapter(
        address parentVault,
        uint256[] memory durations,
        bytes32 salt,
        bytes calldata creationCode
    ) external returns (address) {
        require(keccak256(creationCode) == midnightAdapterCreationCodeHash, InvalidCreationCode());
        bytes memory initCode = bytes.concat(creationCode, abi.encode(parentVault, midnight, durations));
        address _midnightAdapter;
        assembly ("memory-safe") {
            _midnightAdapter := create2(0, add(initCode, 0x20), mload(initCode), salt)
            if iszero(_midnightAdapter) {
                returndatacopy(0, 0, returndatasize())
                revert(0, returndatasize())
            }
        }
        midnightAdapter[parentVault][keccak256(abi.encode(durations))][salt] = _midnightAdapter;
        isMidnightAdapter[_midnightAdapter] = true;
        emit CreateMidnightAdapter(parentVault, durations, salt, _midnightAdapter);
        return _midnightAdapter;
    }
}
