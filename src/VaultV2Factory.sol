// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.28;

import {ErrorsLib} from "./libraries/ErrorsLib.sol";
import {WAD} from "./libraries/ConstantsLib.sol";

import {VaultV2} from "./VaultV2.sol";
import {IVaultV2Factory} from "./interfaces/IVaultV2Factory.sol";

contract VaultV2Factory is IVaultV2Factory {
    mapping(address => bool) public isVaultV2;

    function createVaultV2(address _owner, address _asset) external returns (address) {
        address vaultV2 = address(new VaultV2{salt: 0}(_owner, _asset));

        isVaultV2[vaultV2] = true;

        return vaultV2;
    }
}
