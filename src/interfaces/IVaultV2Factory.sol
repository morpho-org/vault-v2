// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity >=0.5.0;

interface IVaultV2Factory {
    function isVaultV2(address) external view returns (bool);
    function createVaultV2(address, address, bytes32) external returns (address);
}
