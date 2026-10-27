// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.8.0;

import {ERC20Standard} from "../../lib/metamorpho/certora/dispatch/ERC20Standard.sol";

contract LoanToken is ERC20Standard {}

contract CollateralToken is ERC20Standard {}
