// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

library ConstantsLib {
    uint256 constant WAD = 1e18;
    uint256 constant MAX_RATE_PER_SECOND = (1e18 + 200 * 1e16) / uint256(365 days); // 200% APR
}
