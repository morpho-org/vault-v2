// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Morpho Association
pragma solidity 0.8.34;

import {IEnterGate} from "lib/midnight/src/interfaces/IGate.sol";
import {IMidnight, Market} from "lib/midnight/src/interfaces/IMidnight.sol";
import {IdLib} from "lib/midnight/src/libraries/IdLib.sol";

/// @dev Wraps an underlying gate to let vault users be temporarily "admitted" to increase their credit.
/// @dev Lets vault users receive credit through forceDeallocate.
/// @dev Markets other than marketId should not use this gate as their enterGate.
/// @dev The underlying gate must admit only contracts that follow the exit rules, including after revocation.
/// @dev Ordinary contract wallets that can execute arbitrary calls must not receive underlying-gate approval
/// unless cannotAdmit is already set for them.
/// @dev There is no administrative recovery if an unsafe ordinary contract gains credit with cannotAdmit unset.
/// @dev Revoking its underlying-gate approval does not stop it from admitting others while it retains credit.
/// @dev Adapters must reject purchases in their buy callback if cannotAdmit is set for them.
contract WrapperEnterGate is IEnterGate {
    error Unauthorized();

    event CannotAdmit(address indexed account);

    address public immutable midnight;
    bytes32 public immutable marketId;
    /// @dev The underlying gate.
    address public immutable gate;

    /// @dev Once admitted an account cannot admit another account.
    mapping(address account => bool) public cannotAdmit;

    address transient admitted;
    address transient admitter;

    constructor(address _gate, Market memory _market) {
        midnight = _market.midnight;
        gate = _gate;
        _market.enterGate = address(this);
        marketId = IdLib.toId(_market);
    }

    /// @dev Transiently allow a account to increase credit in the market if the account cannot already do so.
    /// @dev TheA contract calling this function should not have debt.
    /// @dev A contract calling this function must clear the buyer immediately after the buyer's take.
    /// @dev Returns whether permission was opened. The buyer's flag is permanent.
    function admit(address user) external returns (bool) {
        // Skip the blacklist so buying does not prevent approved buyers from admitting others.
        // Approved buyers also do not need vault shares.
        if (IEnterGate(gate).canIncreaseCredit(user)) {
            return false;
        } else {
            require(
                msg.sender.code.length > 0 && msg.sender.code[0] != 0xef && !cannotAdmit[msg.sender], Unauthorized()
            );

            require(IMidnight(midnight).credit(marketId, msg.sender) > 0, Unauthorized());
            cannotAdmit[user] = true;
            emit CannotAdmit(user);

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
