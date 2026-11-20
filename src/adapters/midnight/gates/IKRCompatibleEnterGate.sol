// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Morpho Association
pragma solidity 0.8.37;

import {IEnterSubGate} from "./interfaces/IEnterSubGate.sol";
import {IMidnightAdapterFactory} from "../interfaces/IMidnightAdapterFactory.sol";
import {IIKRCompatibleEnterGate} from "./interfaces/IIKRCompatibleEnterGate.sol";

/// @dev Uses a subgate and lets vault users be temporarily "admitted" to increase their credit through forceDeallocate.
/// @dev Any market, on any Midnight, can use this gate as its enterGate. The subgate's permissions apply to all of them.
/// @dev roleSetter permanently registers adapter factories; their debt-free adapters admit a vault shareholder only during their own sale and clear admission in the buyer callback before token transfers.
/// @dev Registered adapter factories are trusted to always return true to isCreated on adapters they deployed, and their adapters must behave correctly. Otherwise, in-kind redemptions can be blocked even when admitEnabled is set to true.
contract IKRCompatibleEnterGate is IIKRCompatibleEnterGate {
    address public immutable subGate;
    /// @dev Immutable to preserve registered vaults' IKR guarantee. When false, markets using this gate won't be usable in vaults that need IKR (enterGateFactory != 0).
    bool public immutable admitEnabled;

    mapping(address account => bool) public admitterFactory;

    address transient admitted;

    constructor(address _subGate, bool _admitEnabled) {
        subGate = _subGate;
        admitEnabled = _admitEnabled;
    }

    function roleSetter() public view returns (address) {
        return IEnterSubGate(subGate).roleSetter(true);
    }

    /// @dev If admitEnabled is false, adding admitter factories has no effect on admission.
    function addAdmitterFactory(address adapterFactory) external {
        require(msg.sender == roleSetter(), Unauthorized());
        admitterFactory[adapterFactory] = true;
        emit AddAdmitterFactory(adapterFactory);
    }

    /// @dev Transiently allow a vault shareholder to increase credit in any market using this gate.
    /// @dev The caller must be debt-free, check the buyer holds its vault's shares, and clear admission in its own sale's buyer callback before token transfers.
    function admit(address user, address adapterFactory) external {
        require(admitEnabled, AdmitDisabled());
        require(
            admitterFactory[adapterFactory] && IMidnightAdapterFactory(adapterFactory).isCreated(msg.sender),
            Unauthorized()
        );
        admitted = user;
        emit Admit(msg.sender, user, adapterFactory);
    }

    /// @dev Clear the admission, should be called from the buyer callback of the buyer's take.
    function unadmit() external {
        admitted = address(0);
    }

    function canIncreaseCredit(address account) external view returns (bool) {
        return (admitted != address(0) && account == admitted) || IEnterSubGate(subGate).creditIncreaseAllowed(account);
    }

    function canIncreaseDebt(address account) external view returns (bool) {
        return IEnterSubGate(subGate).debtIncreaseAllowed(account);
    }
}
