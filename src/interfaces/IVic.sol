// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity >=0.5.0;

interface IVic {
    function interestPerSecond(uint256 totalAssets, uint256 elapsed)
        external
        view
        returns (uint256 interestPerSecond);
}
