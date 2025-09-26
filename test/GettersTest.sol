// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Morpho Association
pragma solidity ^0.8.0;

import "./BaseTest.sol";

contract GettersTest is BaseTest {
    function testDomainSeparator(uint64 chainId) public {
        vm.chainId(chainId);
        assertEq(vault.DOMAIN_SEPARATOR(), computeDomainSeparator(DOMAIN_TYPEHASH, block.chainid, address(vault)));
    }

    function testDecimals(uint8 decimals) public {
        ERC20Mock token = new ERC20Mock(decimals);
        IVaultV2 vault = IVaultV2(vaultFactory.createVaultV2(owner, address(token), bytes32(0)));
        uint256 tokenDecimals = token.decimals();
        uint256 expectedDecimals = tokenDecimals >= 18 ? tokenDecimals : 18;
        assertEq(vault.decimals(), expectedDecimals);
    }

    function testVirtualShares(uint8 decimals) public {
        ERC20Mock token = new ERC20Mock(decimals);
        IVaultV2 vault = IVaultV2(vaultFactory.createVaultV2(owner, address(token), bytes32(0)));
        uint256 tokenDecimals = token.decimals();
        uint256 expectedVirtualShares = tokenDecimals >= 18 ? 1 : 10 ** (18 - tokenDecimals);
        assertEq(vault.virtualShares(), expectedVirtualShares);
    }

    function computeDomainSeparator(bytes32 domainTypehash, uint256 chainId, address account)
        internal
        pure
        returns (bytes32)
    {
        return keccak256(abi.encode(domainTypehash, chainId, account));
    }
}
