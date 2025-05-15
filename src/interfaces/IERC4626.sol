// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity >=0.5.0;

import {IERC20} from "./IERC20.sol";

interface IERC4626 is IERC20 {
    function deposit(uint256 assets, address onBehalf) external returns (uint256 shares);
    function mint(uint256 shares, address onBehalf) external returns (uint256 assets);
    function withdraw(uint256 assets, address onBehalf, address receiver) external returns (uint256 shares);
    function redeem(uint256 shares, address onBehalf, address receiver) external returns (uint256 assets);
}
