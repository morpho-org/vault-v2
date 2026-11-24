// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Morpho Association
pragma solidity 0.8.28;

import {IMidnightAdapterFactory} from "../../adapters/midnight/interfaces/IMidnightAdapterFactory.sol";
import {IMidnightAdapterRegistry} from "./interfaces/IMidnightAdapterRegistry.sol";

contract MidnightAdapterRegistry is IMidnightAdapterRegistry {
    address public immutable midnightAdapterFactory;

    constructor(address _midnightAdapterFactory) {
        midnightAdapterFactory = _midnightAdapterFactory;
    }

    function isInRegistry(address adapter) external view returns (bool) {
        return IMidnightAdapterFactory(midnightAdapterFactory).isCreated(adapter);
    }
}
