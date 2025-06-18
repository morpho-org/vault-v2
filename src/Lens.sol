// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Morpho Association
pragma solidity 0.8.28;

import {Caps} from "./interfaces/IVaultV2.sol";

contract Lens {
    /* ROLES STORAGE */

    address public owner;
    address public curator;
    /// @dev Gates sending and receiving shares.
    /// @dev canSendShares can lock users out of exiting the vault.
    /// @dev canReceiveShares can prevent users from getting back their shares that they deposited on other protocols. If
    /// it reverts or consumes a lot of gas, it can also make accrueInterest revert, thus freezing the vault.
    /// @dev Set to 0 to disable the gate.
    address public sharesGate;
    /// @dev Gates receiving assets from the vault.
    /// @dev Can prevent users from receiving assets from the vault, potentially locking them out of exiting the vault.
    /// @dev Set to 0 to disable the gate.
    address public receiveAssetsGate;
    /// @dev Gates depositing assets to the vault.
    /// @dev This gate is not critical (cannot block users' funds), while still being able to gate supplies.
    /// @dev Set to 0 to disable the gate.
    address public sendAssetsGate;
    mapping(address account => bool) public isSentinel;
    mapping(address account => bool) public isAllocator;

    /* TOKEN STORAGE */

    string public name;
    string public symbol;
    uint256 public totalSupply;
    mapping(address account => uint256) public balanceOf;
    mapping(address owner => mapping(address spender => uint256)) public allowance;
    mapping(address account => uint256) public nonces;

    /* INTEREST STORAGE */

    uint192 internal _totalAssets;
    uint64 public lastUpdate;
    address public vic;
    /// @dev Prevents floashloan-based shorting of vault shares during loss realizations.
    bool public transient enterBlocked;

    /* CURATION STORAGE */

    mapping(address account => bool) public isAdapter;
    /// @dev Ids have an asset allocation, and can be absolutely capped and/or relatively capped.
    /// @dev The allocation is not updated to take interests into account.
    /// @dev Some underlying markets might allow to take into account interest (fixed rate, fixed term), some might not.
    /// @dev The absolute cap is checked on allocate (where allocations can increase) for the ids returned by the
    /// adapter.
    /// @dev The relative cap is relative to `totalAssets`.
    /// @dev Relative caps are "soft" in the sense that they are only checked on allocate for the ids returned by the
    /// adapter.
    /// @dev The relative cap unit is WAD.
    mapping(bytes32 id => Caps) internal caps;
    mapping(address adapter => uint256) public forceDeallocatePenalty;

    /* LIQUIDITY ADAPTER STORAGE */

    address public liquidityAdapter;
    bytes public liquidityData;

    /* TIMELOCKS STORAGE */

    /// @dev The timelock of decreaseTimelock is initially set to TIMELOCK_CAP, and can only be changed to
    /// type(uint256).max through abdicateSubmit..
    /// @dev Only functions with the modifier `timelocked` are timelocked.
    /// @dev Multiple clashing data can be pending, for example increaseCap and decreaseCap, which can make so accepted
    /// timelocked data can potentially be changed shortly afterwards.
    /// @dev The minimum time in which a function can be called is the following:
    /// min(
    ///     timelock[selector],
    ///     executableAt[selector::_],
    ///     executableAt[decreaseTimelock::selector::newTimelock] + newTimelock
    /// ).
    mapping(bytes4 selector => uint256) public timelock;
    /// @dev Nothing is checked on the timelocked data, so it could be not executable (function does not exist,
    /// conditions are not met, etc.).
    mapping(bytes data => uint256) public executableAt;

    /* FEES STORAGE */

    /// @dev Fees unit is WAD.
    /// @dev This invariant holds for both fees: fee != 0 => recipient != address(0).
    uint96 public performanceFee;
    address public performanceFeeRecipient;
    /// @dev Fees unit is WAD.
    /// @dev This invariant holds for both fees: fee != 0 => recipient != address(0).
    uint96 public managementFee;
    address public managementFeeRecipient;

    function absoluteCap(bytes32 id) external view returns (uint256) {
        return caps[id].absoluteCap;
    }

    function relativeCap(bytes32 id) external view returns (uint256) {
        return caps[id].relativeCap;
    }

    function allocation(bytes32 id) external view returns (uint256) {
        return caps[id].allocation;
    }

    /// @dev Gross underestimation because being revert-free cannot be guaranteed when calling the gate.
    function maxDeposit(address) external pure returns (uint256) {
        return 0;
    }

    /// @dev Gross underestimation because being revert-free cannot be guaranteed when calling the gate.
    function maxMint(address) external pure returns (uint256) {
        return 0;
    }

    /// @dev Gross underestimation because being revert-free cannot be guaranteed when calling the gate.
    function maxWithdraw(address) external pure returns (uint256) {
        return 0;
    }

    /// @dev Gross underestimation because being revert-free cannot be guaranteed when calling the gate.
    function maxRedeem(address) external pure returns (uint256) {
        return 0;
    }
}
