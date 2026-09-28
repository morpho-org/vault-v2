// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Morpho Association
pragma solidity 0.8.34;

import {IEnterGate} from "lib/midnight/src/interfaces/IGate.sol";
import {IERC20} from "../../interfaces/IERC20.sol";

contract WrapperEnterGate is IEnterGate {
    address public immutable adapter;
    address public immutable vault;
    address public immutable gate;

    constructor(address _adapter, address _vault, address _gate) {
        adapter = _adapter;
        vault = _vault;
        gate = _gate;
    }

    function canIncreaseCredit(address account) external view returns (bool) {
        return account == adapter || IERC20(vault).balanceOf(account) > 0 || IEnterGate(gate).canIncreaseCredit(account);
    }

    function canIncreaseDebt(address account) external view returns (bool) {
        return IEnterGate(gate).canIncreaseDebt(account);
    }
}
