// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Morpho Association
pragma solidity >=0.5.0;

import {IRatifier} from "lib/midnight/src/interfaces/IRatifier.sol";

interface IMidnightAdapterEcrecoverRatifier is IRatifier {
    /* EVENTS */

    event CancelRoot(address indexed caller, address indexed adapter, bytes32 indexed root);

    /* ERRORS */

    error IncorrectSigner();
    error InvalidProof();
    error NotAuthorized();
    error RootCanceled();

    /* FUNCTIONS */

    function isRootCanceled(address adapter, bytes32 root) external view returns (bool);
    function cancelRoot(address adapter, bytes32 root) external;
}
