// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity >=0.5.0;

interface IGate {
    function canUseShares(address account) external view returns (bool);
    function canUseAssets(address account) external view returns (bool);
    function setHandling(address handlingSetter, address handler, address onBehalf) external;
    function getHandling(address handler) external view returns (address);
}
