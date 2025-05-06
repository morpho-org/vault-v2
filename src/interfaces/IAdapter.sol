// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity >=0.5.0;

interface IAdapter {
    function allocateIn(bytes memory data, uint256 amount) external returns (bytes32[] memory ids);
    function allocateOut(bytes memory data, uint256 amount) external returns (bytes32[] memory ids);
}
