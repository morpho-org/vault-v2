// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Morpho Association
pragma solidity ^0.8.0;

import {ERC20NoRevert} from "../../lib/midnight/test/erc20s/ERC20NoRevert.sol";

contract ERC20NoRevertMock is ERC20NoRevert {
    uint8 public immutable decimals;
    uint256 public totalSupply;

    constructor(uint8 _decimals) ERC20NoRevert("no-revert") {
        decimals = _decimals;
    }
}
