// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Morpho Association
pragma solidity >=0.5.0;

import {IEnterGate} from "../../../../lib/midnight/src/interfaces/IGate.sol";

interface IVaultV2CompatibleEnterGate is IEnterGate {
    /* EVENTS */

    event AddAdmitterFactory(address indexed adapterFactory);
    event Admit(address indexed caller, address indexed user, address indexed adapterFactory);

    /* ERRORS */

    error Unauthorized();
    error AdmitDisabled();

    /* FUNCTIONS */

    function subGate() external view returns (address);
    function admitEnabled() external view returns (bool);
    function canAdmit(address adapterFactory) external view returns (bool);
    function roleSetter() external view returns (address);
    function addAdmitterFactory(address adapterFactory) external;
    function admit(address user, address adapterFactory) external;
    function unadmit() external;
}
