// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Morpho Association
pragma solidity 0.8.34;

// Compile the subgate separately so tests can deploy its artifact with another compiler version.
// forge-lint: disable-next-item(unused-import)
import {
    WhitelistEnterSubGate
} from "../../lib/midnight/src/periphery/whitelist-enter-subgate/WhitelistEnterSubGate.sol";
