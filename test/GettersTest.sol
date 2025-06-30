// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Morpho Association
pragma solidity ^0.8.0;

import "./BaseTest.sol";

contract GettersTest is BaseTest {
    function testDomainSeparator(uint64 chainId) public {
        vm.chainId(chainId);
        assertEq(vault.DOMAIN_SEPARATOR(), computeDomainSeparator(DOMAIN_TYPEHASH, block.chainid, address(vault)));
    }

    function computeDomainSeparator(bytes32 domainTypehash, uint256 chainId, address account)
        internal
        pure
        returns (bytes32)
    {
        return keccak256(abi.encode(domainTypehash, chainId, account));
    }
}
