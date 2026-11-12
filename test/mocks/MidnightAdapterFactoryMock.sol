// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Morpho Association
pragma solidity ^0.8.0;

contract MidnightAdapterFactoryMock {
    mapping(address account => bool) public isCreated;

    function setIsCreated(address account, bool value) external {
        isCreated[account] = value;
    }
}
