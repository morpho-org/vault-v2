// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

library AdapterEventsLib {
    event SetSkimRecipient(address indexed newSkimRecipient);
    event Skim(address indexed token, uint256 amount);
}
