// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Morpho Association
pragma solidity >=0.5.0;

import {IWhitelistEnterGate} from "lib/midnight/src/periphery/whitelist-enter-gate/interfaces/IWhitelistEnterGate.sol";

interface IForceDeallocationEnterGate is IWhitelistEnterGate {
    error Unauthorized();

    event AddAdapterFactory(address indexed adapterFactory);

    function isAdapterFactory(address adapterFactory) external view returns (bool);
    function addAdapterFactory(address adapterFactory) external;
    function transientAllowIncreaseCredit(address user, address adapter, address adapterFactory) external;
    function transientAdapter(address user) external view returns (address);
    function isTransientlyAllowed(address user) external view returns (bool);
}
