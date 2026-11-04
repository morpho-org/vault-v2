// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Morpho Association
pragma solidity ^0.8.0;

import {ERC20USDT} from "../../lib/midnight/test/erc20s/ERC20USDT.sol";

contract ERC20USDTMock is ERC20USDT {
    uint8 public immutable decimals;
    uint256 public totalSupply;

    constructor(uint8 _decimals) ERC20USDT("usdt") {
        decimals = _decimals;
    }
}
