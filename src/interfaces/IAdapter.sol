// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity >=0.5.0;

interface IAdapter {
    function allocate(bytes memory data, uint256 assets) external returns (bytes32[] memory ids, uint256 loss);
    function deallocate(bytes memory data, uint256 assets) external returns (bytes32[] memory ids, uint256 loss);
}
