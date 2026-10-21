// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Morpho Association
pragma solidity 0.8.37;

import {Market} from "../../../lib/midnight/src/interfaces/IMidnight.sol";
import {IdLib} from "../../../lib/midnight/src/libraries/IdLib.sol";
import {VaultV2CompatibleEnterGate} from "./VaultV2CompatibleEnterGate.sol";
import {IVaultV2CompatibleEnterGateFactory} from "./interfaces/IVaultV2CompatibleEnterGateFactory.sol";

contract VaultV2CompatibleEnterGateFactory is IVaultV2CompatibleEnterGateFactory {
    mapping(address account => mapping(bytes32 marketId => bool)) public isGate;
    /// @dev marketIdWithoutGate is the id of the market with enterGate set to zero.
    mapping(address subGate => mapping(bytes32 marketIdWithoutGate => mapping(bytes32 salt => address))) public
        vaultV2CompatibleEnterGate;

    function createVaultV2CompatibleEnterGate(address subGate, Market memory market, bytes32 salt)
        external
        returns (address)
    {
        require(market.enterGate == address(0), NonZeroEnterGate());
        address gate = address(new VaultV2CompatibleEnterGate{salt: salt}(subGate, market));
        vaultV2CompatibleEnterGate[subGate][IdLib.toId(market)][salt] = gate;
        bytes32 marketId = VaultV2CompatibleEnterGate(gate).marketId();
        isGate[gate][marketId] = true;
        emit CreateVaultV2CompatibleEnterGate(gate, subGate, marketId);
        return gate;
    }
}
