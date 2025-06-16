// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity >=0.5.0;

/// @dev See VaultV2 Natspec for more details on adapter's spec.
interface IAdapter {
    /// @dev Returns the market' ids and the PnL on this market.
    function updateAllocation(bytes memory data) external returns (bytes32[] memory ids, int256 change);
    /// @dev Returns the market' ids.
    function allocate(bytes memory data, uint256 assets) external returns (bytes32[] memory ids);
    /// @dev Returns the market' ids.
    function deallocate(bytes memory data, uint256 assets) external returns (bytes32[] memory ids);
}
