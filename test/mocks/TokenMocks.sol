// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Morpho Association
pragma solidity ^0.8.0;

import {IERC20} from "../../src/interfaces/IERC20.sol";
import {ERC20Mock} from "./ERC20Mock.sol";
import {ERC20NoRevertMock} from "./ERC20NoRevertMock.sol";
import {ERC20USDTMock} from "./ERC20USDTMock.sol";
import {ERC20RevertToZeroMock} from "./ERC20RevertToZeroMock.sol";
import {ERC20NoReturnMock} from "./ERC20NoReturnMock.sol";

function newTokenOfType(uint256 tokenType, uint8 decimals) returns (IERC20) {
    if (tokenType == 1) return IERC20(address(new ERC20NoRevertMock(decimals)));
    if (tokenType == 2) return IERC20(address(new ERC20USDTMock(decimals)));
    if (tokenType == 3) return IERC20(address(new ERC20RevertToZeroMock(decimals)));
    if (tokenType == 4) return IERC20(address(new ERC20NoReturnMock(decimals)));
    return IERC20(address(new ERC20Mock(decimals)));
}
