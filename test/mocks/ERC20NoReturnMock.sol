// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Morpho Association
pragma solidity ^0.8.0;

import {ERC20NoReturn} from "../../lib/midnight/test/erc20s/ERC20NoReturn.sol";

contract ERC20NoReturnMock is ERC20NoReturn {
    uint8 public immutable decimals;
    uint256 public totalSupply;

    constructor(uint8 _decimals) ERC20NoReturn("no-return") {
        decimals = _decimals;
    }
}
