// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity >=0.5.0;

interface IAdapter {
    function reallocateFromAdapter(bytes memory data, uint256 assets) external returns (bytes32[] memory ids);
    function reallocateToAdapter(bytes memory data, uint256 assets) external returns (bytes32[] memory ids);
}
