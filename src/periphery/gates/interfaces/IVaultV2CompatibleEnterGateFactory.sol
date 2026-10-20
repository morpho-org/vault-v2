// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Morpho Association
pragma solidity >=0.5.0;

import {IEnterGateFactory} from "../../../../lib/midnight/src/interfaces/IEnterGateFactory.sol";
import {Market} from "../../../../lib/midnight/src/interfaces/IMidnight.sol";

interface IVaultV2CompatibleEnterGateFactory is IEnterGateFactory {
    /* EVENTS */

    event CreateVaultV2CompatibleEnterGate(
        address indexed vaultV2CompatibleEnterGate, address indexed subGate, bytes32 marketId
    );

    /* ERRORS */

    error NonZeroEnterGate();

    /* FUNCTIONS */

    function initialAdapterFactory() external view returns (address);
    function createVaultV2CompatibleEnterGate(address subGate, Market memory market, bytes32 salt)
        external
        returns (address);
}
