// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity >=0.5.0;

import {IERC20} from "./IERC20.sol";

interface IERC4626 is IERC20 {
    function deposit(uint256, address) external returns (uint256);
    function mint(uint256, address) external returns (uint256);
    function redeem(uint256, address, address) external returns (uint256);
    function withdraw(uint256, address, address) external returns (uint256);
}
