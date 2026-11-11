// SPDX-License-Identifier: MIT
// Copyright (c) 2025 Morpho Association
pragma solidity 0.8.37;

import {MidnightAdapter} from "./MidnightAdapter.sol";
import {IMidnightAdapterFactory} from "./interfaces/IMidnightAdapterFactory.sol";

contract MidnightAdapterFactory is IMidnightAdapterFactory {
    /* IMMUTABLES */

    address public immutable midnight;
    bytes32 public immutable adapterCodeHash;

    /* STORAGE */

    mapping(address account => bool) public isCreated;

    /* CONSTRUCTOR */

    constructor(address _midnight) {
        midnight = _midnight;
        adapterCodeHash = keccak256(type(MidnightAdapter).creationCode);
        emit CreateMidnightAdapterFactory(_midnight);
    }

    /* FUNCTIONS */

    /// @dev The array of capped durations must be of size <= 8, and strictly increasing. Durations must be > 0 and fit on 32 bits.
    /// @dev enterGateFactory is address(0) for ungated adapters; otherwise see the ENTER GATE requirements in MidnightAdapter.
    /// @dev The salt is derived from msg.sender to prevent front-running issues. Bundles (shared msg.sender) must derive preSalt from the initiator too.
    function createMidnightAdapter(
        address parentVault,
        uint256[] memory durations,
        address enterGateFactory,
        bytes32 preSalt,
        bytes memory code
    ) external returns (address) {
        require(keccak256(code) == adapterCodeHash, InvalidAdapterCode());
        bytes32 salt = keccak256(abi.encode(preSalt, msg.sender));
        bytes memory initCode = bytes.concat(code, abi.encode(parentVault, midnight, durations, enterGateFactory));
        address _midnightAdapter;
        assembly ("memory-safe") {
            _midnightAdapter := create2(0, add(initCode, 32), mload(initCode), salt)
            if iszero(_midnightAdapter) {
                let ptr := mload(0x40)
                returndatacopy(ptr, 0, returndatasize())
                revert(ptr, returndatasize())
            }
        }
        isCreated[_midnightAdapter] = true;
        emit CreateMidnightAdapter(msg.sender, parentVault, durations, preSalt, _midnightAdapter, enterGateFactory);
        return _midnightAdapter;
    }
}
