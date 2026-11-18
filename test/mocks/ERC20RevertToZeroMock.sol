// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Morpho Association
pragma solidity ^0.8.0;

import {ERC20RevertToZero} from "../../lib/midnight/test/erc20s/ERC20RevertToZero.sol";

contract ERC20RevertToZeroMock is ERC20RevertToZero {
    uint8 public immutable decimals;
    uint256 public totalSupply;

    constructor(uint8 _decimals) ERC20RevertToZero("revert-to-zero") {
        decimals = _decimals;
    }
}
