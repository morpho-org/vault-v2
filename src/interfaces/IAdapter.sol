// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity >=0.5.0;

/// @dev See VaultV2 Natspec for more details on adapter's spec.
interface IAdapter {
    /// @dev Returns the market' ids, the interest accrued on this market, and the actual assets gained by the adapter.
    function allocate(bytes memory data, uint256 assets)
        external
        returns (bytes32[] memory ids, uint256 interest, uint256 gainedAssets);

    /// @dev Returns the market' ids, the interest accrued on this market, and the actual assets lost by the adapter.
    function deallocate(bytes memory data, uint256 assets)
        external
        returns (bytes32[] memory ids, uint256 interest, uint256 lostAssets);

    /// @dev Returns the market' ids and the loss occurred on this market.
    function realizeLoss(bytes memory data) external returns (bytes32[] memory ids, uint256 loss);
}
