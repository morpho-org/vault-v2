// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Morpho Association
pragma solidity 0.8.28;

import {IOnchainVicFactory} from "./interfaces/IOnchainVicFactory.sol";

import {OnchainVic} from "./OnchainVic.sol";

contract OnchainVicFactory is IOnchainVicFactory {
    /*  STORAGE */

    mapping(address vault => address) public onchainVic;
    mapping(address account => bool) public isOnchainVic;

    /* FUNCTIONS */

    /// @dev Returns the address of the deployed OnchainVic.
    function createOnchainVic(address vault) external returns (address) {
        address vic = address(new OnchainVic{salt: bytes32(0)}(vault));

        isOnchainVic[vic] = true;
        onchainVic[vault] = vic;
        emit CreateOnchainVic(vic, vault);

        return vic;
    }
}
