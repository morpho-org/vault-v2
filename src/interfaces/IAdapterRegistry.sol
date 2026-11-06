// SPDX-License-Identifier: MIT
// Copyright (c) 2025 Morpho Association
pragma solidity >=0.5.0;

interface IAdapterRegistry {
    function isInRegistry(address account) external view returns (bool);
}
