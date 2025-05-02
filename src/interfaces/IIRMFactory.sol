// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity >=0.5.0;

interface IIrmFactory {
    function isIrm(address) external view returns (bool);
    function createIrm(address owner, bytes32 salt) external returns (address);
}
