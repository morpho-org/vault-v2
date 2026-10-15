// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Morpho Association
pragma solidity 0.8.37;

import {IEnterGate} from "lib/midnight/src/interfaces/IGate.sol";
import {IMidnight, Market} from "lib/midnight/src/interfaces/IMidnight.sol";
import {IdLib} from "lib/midnight/src/libraries/IdLib.sol";
import {IRoleSetter} from "./interfaces/IRoleSetter.sol";

/// @dev Wraps an underlying gate to let vault users be temporarily "admitted" to increase their credit.
/// @dev Lets vault users receive credit through forceDeallocate.
/// @dev Markets other than marketId should not use this gate as their enterGate.
/// @dev roleSetter must register only contracts that follow the admission rules, including after upgrades.
/// @dev Registration is permanent. Revoking underlying-gate approval does not revoke canAdmit.
contract WrapperEnterGate is IEnterGate {
    error Unauthorized();

    event SetCanAdmit(address indexed account);

    address public immutable midnight;
    bytes32 public immutable marketId;
    /// @dev The underlying gate.
    address public immutable gate;

    mapping(address account => bool) public canAdmit;

    address transient admitted;
    address transient admitter;

    constructor(address _gate, Market memory _market) {
        midnight = _market.midnight;
        gate = _gate;
        _market.enterGate = address(this);
        marketId = IdLib.toId(_market);
    }

    function roleSetter() public view returns (address) {
        return IRoleSetter(gate).roleSetter(true);
    }

    function setCanAdmit(address account) external {
        require(msg.sender == roleSetter(), Unauthorized());
        canAdmit[account] = true;
        emit SetCanAdmit(account);
    }

    /// @dev Transiently allow a account to increase credit in the market if the account cannot already do so.
    /// @dev The contract calling this function should not have debt.
    /// @dev A contract calling this function must clear the buyer immediately after the buyer's take.
    /// @dev Returns whether permission was opened.
    function admit(address user) external returns (bool) {
        // Buyers already allowed by the underlying gate do not need vault shares.
        if (IEnterGate(gate).canIncreaseCredit(user)) {
            return false;
        } else {
            require(canAdmit[msg.sender], Unauthorized());

            admitted = user;
            admitter = msg.sender;
            return true;
        }
    }

    function unadmit() external {
        admitted = address(0);
        admitter = address(0);
    }

    /// @dev Midnight locks the seller before callbacks, disabling the exception during reentrancy.
    function canIncreaseCredit(address account) external view returns (bool) {
        return (account == admitted && !IMidnight(midnight).liquidationLocked(marketId, admitter))
            || IEnterGate(gate).canIncreaseCredit(account);
    }

    function canIncreaseDebt(address account) external view returns (bool) {
        return IEnterGate(gate).canIncreaseDebt(account);
    }
}
