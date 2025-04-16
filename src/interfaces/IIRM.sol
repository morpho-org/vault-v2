// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity >=0.5.0;

interface IIRM {
    function owner() external view returns (address);
    function setInterestPerSecond(uint256) external;
    function accruedInterest(uint256, uint256) external view returns (uint256);
}
