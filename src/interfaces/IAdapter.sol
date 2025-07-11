// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Morpho Association
pragma solidity >=0.5.0;

/// @dev See VaultV2 Natspec for more details on adapter's spec.
interface IAdapter {
    /// @dev Returns the market' ids and the interest accrued on this market.
    function allocate(bytes memory data, uint256 assets, bytes4 selector, address sender)
        external
        returns (bytes32[] memory ids, uint256 interest);

    /// @dev Returns the market' ids and the interest accrued on this market.
    function deallocate(bytes memory data, uint256 assets, bytes4 selector, address sender)
        external
        returns (bytes32[] memory ids, uint256 interest);

    /// @dev Returns the market' ids and the loss occurred on this market.
    function realizeLoss(bytes memory data, bytes4 selector, address sender)
        external
        returns (bytes32[] memory ids, uint256 loss);
}
