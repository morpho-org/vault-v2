// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity >=0.5.0;

interface IVaultV2Factory {
    function isVaultV2(address account) external view returns (bool);
    function createVaultV2(address owner, address asset, string memory name, string memory symbol, bytes32 salt)
        external
        returns (address vaultV2);
}
