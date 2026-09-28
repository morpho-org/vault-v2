// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Morpho Association
pragma solidity 0.8.34;

import {IEnterGate} from "lib/midnight/src/interfaces/IGate.sol";
import {IMidnight, Market} from "lib/midnight/src/interfaces/IMidnight.sol";
import {IdLib} from "lib/midnight/src/libraries/IdLib.sol";
import {IMidnightAdapter} from "../../adapters/interfaces/IMidnightAdapter.sol";
import {IERC20} from "../../interfaces/IERC20.sol";

/// @dev Lets in users of vaults present in a specific market.
/// @dev Markets other than marketId should not use this gate as their enterGate.
/// @dev Adapters with market credit are trusted to report their parent vault honestly.
contract WrapperEnterGate is IEnterGate {
    error Unauthorized();

    address public immutable midnight;
    bytes32 public immutable marketId;
    address public immutable gate;

    constructor(address _gate, Market memory market) {
        midnight = market.midnight;
        gate = _gate;
        market.enterGate = address(this);
        marketId = IdLib.toId(market);
    }

    /// @dev Authorization lasts until the end of the transaction, even if shares or credit are subsequently removed.
    function transientAllowIncreaseCredit(address user, address adapter) external {
        require(
            IERC20(IMidnightAdapter(adapter).parentVault()).balanceOf(user) > 0
                && IMidnight(midnight).credit(marketId, adapter) > 0,
            Unauthorized()
        );

        bytes32 slot = keccak256(abi.encode(user));
        assembly ("memory-safe") {
            tstore(slot, 1)
        }
    }

    function isTransientlyAllowed(address user) public view returns (bool allowed) {
        bytes32 slot = keccak256(abi.encode(user));
        assembly ("memory-safe") {
            allowed := tload(slot)
        }
    }

    function canIncreaseCredit(address account) external view returns (bool) {
        return isTransientlyAllowed(account) || IEnterGate(gate).canIncreaseCredit(account);
    }

    function canIncreaseDebt(address account) external view returns (bool) {
        return IEnterGate(gate).canIncreaseDebt(account);
    }
}
