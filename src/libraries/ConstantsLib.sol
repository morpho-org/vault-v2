// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

uint256 constant WAD = 1e18;
bytes32 constant DOMAIN_TYPEHASH = keccak256("EIP712Domain(uint256 chainId,address verifyingContract)");
bytes32 constant PERMIT_TYPEHASH =
    keccak256("Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)");
