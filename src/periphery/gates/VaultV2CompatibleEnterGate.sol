// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Morpho Association
pragma solidity 0.8.37;

import {IEnterSubGate} from "./interfaces/IEnterSubGate.sol";
import {IMidnightAdapterFactory} from "../../adapters/interfaces/IMidnightAdapterFactory.sol";
import {IVaultV2CompatibleEnterGate} from "./interfaces/IVaultV2CompatibleEnterGate.sol";

/// @dev Uses a subgate and lets vault users be temporarily "admitted" to increase their credit through forceDeallocate
/// @dev Any market, on any Midnight, can use this gate as its enterGate. The subgate's permissions apply to all of them.
/// @dev roleSetter must register only factories whose adapters follow the admission rules, including after upgrades.
/// @dev Registered factories must not revoke adapter membership.
/// @dev Registration is permanent. Revoking subgate approval does not revoke canAdmit.
/// @dev No factory can admit until roleSetter calls addAdmitterFactory.
contract VaultV2CompatibleEnterGate is IVaultV2CompatibleEnterGate {
    /// @dev The underlying subgate.
    address public immutable subGate;

    mapping(address factory => bool) public canAdmit;

    address transient admitted;

    constructor(address _subGate) {
        subGate = _subGate;
    }

    function roleSetter() public view returns (address) {
        return IEnterSubGate(subGate).roleSetter(true);
    }

    function addAdmitterFactory(address factory) external {
        require(msg.sender == roleSetter(), Unauthorized());
        canAdmit[factory] = true;
        emit AddAdmitterFactory(factory);
    }

    /// @dev Transiently allow a vault shareholder to increase credit in any market of this gate.
    /// @dev The contract calling this function should not have debt.
    /// @dev The caller must use admission only for its own sale.
    /// @dev The caller must take a buy offer without a callback.
    /// @dev A contract calling this function must clear the buyer immediately after the buyer's take.
    /// @dev The caller must check that the buyer holds shares in its parent vault.
    function admit(address user, address factory) external {
        require(canAdmit[factory] && IMidnightAdapterFactory(factory).isCreated(msg.sender), Unauthorized());

        admitted = user;
    }

    /// @dev Clear the admission, should be called after taking the buyer's offer.
    function unadmit() external {
        admitted = address(0);
    }


    function canIncreaseCredit(address account) external view returns (bool) {
        return (admitted != address(0) && account == admitted) || IEnterSubGate(subGate).canIncreaseCredit(account);
    }

    function canIncreaseDebt(address account) external view returns (bool) {
        return IEnterSubGate(subGate).canIncreaseDebt(account);
    }
}
