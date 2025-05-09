// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity >=0.5.0;

interface ISendGate {
    function canSendShares(address account, address assetReceive) external view returns (bool);
}

interface IReceiveGate {
    function canReceiveShares(address account, address assetSender) external view returns (bool);
}
