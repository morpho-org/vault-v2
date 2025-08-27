// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Morpho Association
pragma solidity >=0.5.0;

interface IWhitelister {
    function whitelisted(address account) external view returns (bool);
}
