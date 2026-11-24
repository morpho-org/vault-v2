// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Morpho Association
pragma solidity >=0.5.0;

import {IAdapterRegistry} from "../../../interfaces/IAdapterRegistry.sol";

interface IMidnightRegistry is IAdapterRegistry {
    function midnightAdapterFactory() external view returns (address);
}
