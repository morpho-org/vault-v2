// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Morpho Association
pragma solidity >=0.5.0;

import {IEnterGate} from "../../../../lib/midnight/src/interfaces/IGate.sol";
import {Offer} from "../../../../lib/midnight/src/interfaces/IMidnight.sol";

interface IVaultV2CompatibleEnterGate is IEnterGate {
    /* EVENTS */

    event AddAdmitterFactory(address indexed factory);
    event Admit(address indexed caller, address indexed user, address indexed factory);
    event BuyAtZero(address indexed caller, bytes32 indexed marketId, uint256 units);

    /* ERRORS */

    error Unauthorized();
    error IncorrectOffer();

    /* FUNCTIONS */

    function subGate() external view returns (address);
    function canAdmit(address factory) external view returns (bool);
    function roleSetter() external view returns (address);
    function addAdmitterFactory(address factory) external;
    function admit(address user, address factory) external;
    function unadmit() external;
    function buyAtZero(Offer memory offer, bytes memory ratifierData, uint256 units) external;
}
