// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity >=0.5.0;

interface IGate {
    function canSendShares(address account) external view returns (bool);
    function canReceiveShares(address account) external view returns (bool);
    function canSupplyAssets(address account) external view returns (bool);
    function canWithdrawAssets(address account) external view returns (bool);
}
