// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Morpho Association
pragma solidity >=0.5.0;

import {IEnterGate} from "../../../../lib/midnight/src/interfaces/IGate.sol";

interface IVaultV2CompatibleEnterGate is IEnterGate {
    /* EVENTS */

    event AddAdmitterFactory(address indexed factory);

    /* ERRORS */

    error Unauthorized();

    /* FUNCTIONS */

    function midnight() external view returns (address);
    function marketId() external view returns (bytes32);
    function subGate() external view returns (address);
    function canAdmit(address factory) external view returns (bool);
    function roleSetter() external view returns (address);
    function addAdmitterFactory(address factory) external;
    function admit(address user, address factory) external;
    function unadmit() external;
}
