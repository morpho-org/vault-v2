// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Morpho Association
pragma solidity 0.8.37;

import {WhitelistEnterSubGate} from "./WhitelistEnterSubGate.sol";
import {IWhitelistEnterSubGateFactory} from "./interfaces/IWhitelistEnterSubGateFactory.sol";

contract WhitelistEnterSubGateFactory is IWhitelistEnterSubGateFactory {
    mapping(address subGate => bool) public isCreated;
    mapping(
        address creditRoleSetter
            => mapping(
            address debtRoleSetter
                => mapping(bool creditOpen => mapping(bool debtOpen => mapping(bytes32 salt => address)))
        )
    ) public whitelistEnterSubGate;

    /// @dev The salt is derived from msg.sender to prevent front-running issues. Bundles (shared msg.sender) must derive preSalt from the initiator too.
    function createWhitelistEnterSubGate(
        address creditRoleSetter,
        address debtRoleSetter,
        bool creditOpen,
        bool debtOpen,
        bytes32 preSalt
    ) external returns (address) {
        bytes32 salt = keccak256(abi.encode(preSalt, msg.sender));
        address subGate =
            address(new WhitelistEnterSubGate{salt: salt}(creditRoleSetter, debtRoleSetter, creditOpen, debtOpen));
        whitelistEnterSubGate[creditRoleSetter][debtRoleSetter][creditOpen][debtOpen][salt] = subGate;
        isCreated[subGate] = true;

        emit CreateWhitelistEnterSubGate(
            msg.sender, subGate, creditRoleSetter, debtRoleSetter, creditOpen, debtOpen, preSalt
        );
        return subGate;
    }
}
