// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Morpho Association
pragma solidity ^0.8.0;

import {IAdapter} from "../../src/interfaces/IAdapter.sol";

/// @notice Minimal stub contract used as the parent vault to test adapters.
contract VaultV2Mock {
    address public asset;
    address public owner;
    address public curator;
    mapping(address => bool) public isAllocator;
    mapping(address => bool) public isSentinel;
    mapping(bytes32 => uint256) public allocation;

    constructor(address _asset, address _owner, address _curator, address _allocator, address _sentinel) {
        asset = _asset;
        owner = _owner;
        curator = _curator;
        isAllocator[_allocator] = true;
        isSentinel[_sentinel] = true;
    }

    function accrueInterest() public {}

    function allocateMocked(address adapter, bytes memory data, uint256 assets)
        external
        returns (bytes32[] memory, int256)
    {
        (bytes32[] memory ids, int256 change) = IAdapter(adapter).allocate(data, assets, msg.sig, msg.sender);
        for (uint256 i; i < ids.length; i++) {
            allocation[ids[i]] = uint256(int256(allocation[ids[i]]) + change);
        }
        return (ids, change);
    }

    function deallocateMocked(address adapter, bytes memory data, uint256 assets)
        external
        returns (bytes32[] memory, int256)
    {
        (bytes32[] memory ids, int256 change) = IAdapter(adapter).deallocate(data, assets, msg.sig, msg.sender);
        for (uint256 i; i < ids.length; i++) {
            allocation[ids[i]] = uint256(int256(allocation[ids[i]]) + change);
        }
        return (ids, change);
    }
}
