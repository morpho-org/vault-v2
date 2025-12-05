// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.28;

import {IERC20, SafeERC20Lib} from "../../src/libraries/SafeERC20Lib.sol";

contract ERC20Helper {
    function balanceOf(address token, address user) external view returns (uint256) {
        return IERC20(token).balanceOf(user);
    }

    function totalSupply(address token) external view returns (uint256) {
        return IERC20(token).totalSupply();
    }

    function safeTransferFrom(address token, address from, address to, uint256 amount) external {
        SafeERC20Lib.safeTransferFrom(token, from, to, amount);
    }
}
