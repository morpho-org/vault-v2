// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity >=0.5.0;

interface IPermissionedToken {
    function canSend(address account) external view returns (bool);
    function canReceive(address account) external view returns (bool);
}
