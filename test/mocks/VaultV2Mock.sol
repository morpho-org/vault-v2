// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

/// @notice Minimal stub contract used as the parent vault to test adapters.
contract VaultV2Mock {
    address public asset;
    address public owner;
    address public curator;
    mapping(address => bool) public isAllocator;
    mapping(address => bool) public isSentinel;

    constructor(address _asset, address _owner, address _curator, address _allocator, address _sentinel) {
        asset = _asset;
        owner = _owner;
        curator = _curator;
        isAllocator[_allocator] = true;
        isSentinel[_sentinel] = true;
    }

    function accrueInterest() public {}
}
