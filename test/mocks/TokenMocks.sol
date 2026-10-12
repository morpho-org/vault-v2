// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Morpho Association
pragma solidity ^0.8.0;

import {IERC20} from "../../src/interfaces/IERC20.sol";
import {ERC20Mock} from "./ERC20Mock.sol";
import {ERC20NoRevert} from "../../lib/midnight/test/erc20s/ERC20NoRevert.sol";
import {ERC20USDT} from "../../lib/midnight/test/erc20s/ERC20USDT.sol";
import {ERC20RevertToZero} from "../../lib/midnight/test/erc20s/ERC20RevertToZero.sol";
import {ERC20NoReturn} from "../../lib/midnight/test/erc20s/ERC20NoReturn.sol";

contract ERC20NoRevertMock is ERC20NoRevert {
    uint8 public immutable decimals;
    uint256 public totalSupply;

    constructor(uint8 _decimals) ERC20NoRevert("no-revert") {
        decimals = _decimals;
    }
}

contract ERC20USDTMock is ERC20USDT {
    uint8 public immutable decimals;
    uint256 public totalSupply;

    constructor(uint8 _decimals) ERC20USDT("usdt") {
        decimals = _decimals;
    }
}

contract ERC20RevertToZeroMock is ERC20RevertToZero {
    uint8 public immutable decimals;
    uint256 public totalSupply;

    constructor(uint8 _decimals) ERC20RevertToZero("revert-to-zero") {
        decimals = _decimals;
    }
}

contract ERC20NoReturnMock is ERC20NoReturn {
    uint8 public immutable decimals;
    uint256 public totalSupply;

    constructor(uint8 _decimals) ERC20NoReturn("no-return") {
        decimals = _decimals;
    }
}

// TOKEN_TYPE values: 0 standard, 1 no-revert, 2 usdt, 3 revert-to-zero, 4 no-return.
function newTokenOfType(uint256 tokenType, uint8 decimals) returns (IERC20) {
    if (tokenType == 1) return IERC20(address(new ERC20NoRevertMock(decimals)));
    if (tokenType == 2) return IERC20(address(new ERC20USDTMock(decimals)));
    if (tokenType == 3) return IERC20(address(new ERC20RevertToZeroMock(decimals)));
    if (tokenType == 4) return IERC20(address(new ERC20NoReturnMock(decimals)));
    return IERC20(address(new ERC20Mock(decimals)));
}
