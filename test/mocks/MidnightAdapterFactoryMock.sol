// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Morpho Association
pragma solidity ^0.8.0;

contract MidnightAdapterFactoryMock {
    mapping(address account => bool) public isMidnightAdapter;

    function setIsMidnightAdapter(address account, bool value) external {
        isMidnightAdapter[account] = value;
    }
}
