// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity >=0.5.0;

interface IPermissionedTokenHandler {
    function permissionedTokenHandlerCallback(address onBehalf, uint256 amount, bytes calldata callback) external;
}
