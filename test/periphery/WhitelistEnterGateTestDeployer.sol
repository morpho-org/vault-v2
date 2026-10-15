// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Morpho Association
pragma solidity 0.8.34;

import {WhitelistEnterGate} from "../../lib/midnight/src/periphery/whitelist-enter-gate/WhitelistEnterGate.sol";

contract WhitelistEnterGateTestDeployer {
    function deploy(address creditRoleSetter, address debtRoleSetter, bool creditOpen, bool debtOpen)
        external
        returns (address)
    {
        return address(new WhitelistEnterGate(creditRoleSetter, debtRoleSetter, creditOpen, debtOpen));
    }
}
