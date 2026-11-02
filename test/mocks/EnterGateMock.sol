// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Morpho Association
pragma solidity ^0.8.0;

import {IEnterGate} from "../../lib/midnight/src/interfaces/IGate.sol";

contract EnterGateMock is IEnterGate {
    mapping(address account => bool) public canIncreaseCredit;
    mapping(address account => bool) public canIncreaseDebt;

    function setCanIncreaseCredit(address account, bool allowed) external {
        canIncreaseCredit[account] = allowed;
    }

    function setCanIncreaseDebt(address account, bool allowed) external {
        canIncreaseDebt[account] = allowed;
    }
}
