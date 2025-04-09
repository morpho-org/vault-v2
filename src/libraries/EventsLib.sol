// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.28;

library EventsLib {
    event Transfer(address indexed from, address indexed to, uint256 amount);
    event Approval(address indexed owner, address indexed spender, uint256 amount);
}
