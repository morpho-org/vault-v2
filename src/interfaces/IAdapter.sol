// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity >=0.5.0;

/// @dev See VaultV2 Natspec for more details on adapter's spec.
interface IAdapter {
    /// @dev Returns the market' ids, the interest accrued and the loss realized.
    function allocate(bytes memory data, uint256 assets)
        external
        returns (bytes32[] memory ids, uint256 interest, uint256 loss);

    /// @dev Returns the market' ids, the interest accrued and the loss realized.
    function deallocate(bytes memory data, uint256 assets)
        external
        returns (bytes32[] memory ids, uint256 interest, uint256 loss);
}
