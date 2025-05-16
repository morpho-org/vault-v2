// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

uint256 constant WAD = 1e18;
bytes32 constant DOMAIN_TYPEHASH = keccak256("EIP712Domain(uint256 chainId,address verifyingContract)");
bytes32 constant PERMIT_TYPEHASH =
    keccak256("Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)");
uint256 constant MAX_RATE_PER_SECOND = (1e18 + 200 * 1e16) / uint256(365 days); // 200% APR
uint256 constant TIMELOCK_CAP = 2 weeks;
uint256 constant MAX_PERFORMANCE_FEE = 0.5e18; // 50%
uint256 constant MAX_MANAGEMENT_FEE = 0.05e18 / uint256(365 days); // 5%
uint256 constant MAX_FORCE_DEALLOCATE_PENALTY = 0.01e18; // 1%
uint256 constant EXIT_BUFFER_TIME = 15 minutes; // time to fully empty exit buffer; with continuous decay
uint256 constant EXIT_BUFFER_SIZE = 0.125e18; // 12.5%
