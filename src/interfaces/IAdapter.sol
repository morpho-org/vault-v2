// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Morpho Association
pragma solidity >=0.5.0;

/// @dev See VaultV2 Natspec for more details on adapter's spec.
interface IAdapter {
    /// @dev Returns the market' ids and the loss occurred on this market.
    function allocate(bytes memory data, uint256 assets) external returns (bytes32[] memory ids, uint256 loss);

    /// @dev Returns the market' ids and the loss occurred on this market.
    function deallocate(bytes memory data, uint256 assets) external returns (bytes32[] memory ids, uint256 loss);
}
