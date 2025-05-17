// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity >=0.5.0;

interface IExitGate {
    function canSendShares(address account) external view returns (bool);
    function canReceiveAssets(address account) external view returns (bool);
}

interface IEnterGate {
    function canReceiveShares(address account) external view returns (bool);
    function canSendAssets(address account) external view returns (bool);
}
