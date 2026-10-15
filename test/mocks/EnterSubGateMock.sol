// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Morpho Association
pragma solidity ^0.8.0;

import {IEnterSubGate} from "../../lib/midnight/src/interfaces/IEnterSubGate.sol";

contract EnterSubGateMock is IEnterSubGate {
    mapping(bool creditSide => address) public roleSetter;
    mapping(bytes32 marketId => mapping(address account => bool)) public canIncreaseCredit;
    mapping(bytes32 marketId => mapping(address account => bool)) public canIncreaseDebt;

    constructor() {
        roleSetter[true] = msg.sender;
    }

    function setCanIncreaseCredit(bytes32 marketId, address account, bool allowed) external {
        canIncreaseCredit[marketId][account] = allowed;
    }

    function setCanIncreaseDebt(bytes32 marketId, address account, bool allowed) external {
        canIncreaseDebt[marketId][account] = allowed;
    }
}
