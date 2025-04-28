// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity >=0.5.0;

interface IGatekeeper {
    function canWithdraw(address sender, address receiver, address onBehalf) external view returns (bool);
    function canTransfer(address sender, address from, address to) external view returns (bool);
}
