// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Morpho Association
pragma solidity >=0.5.0;

import {IRatifier} from "lib/midnight/src/interfaces/IRatifier.sol";

interface IMidnightAdapterSetterRatifier is IRatifier {
    /* EVENTS */

    event SetIsRootRatified(
        address indexed caller, address indexed adapter, bytes32 indexed root, bool newIsRootRatified
    );

    /* ERRORS */

    error InvalidProof();
    error NotAuthorized();
    error NotRatified();

    /* FUNCTIONS */

    function isRootRatified(address adapter, bytes32 root) external view returns (bool);
    function setIsRootRatified(address adapter, bytes32 root, bool newIsRootRatified) external;
}
