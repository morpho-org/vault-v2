// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Morpho Association
pragma solidity ^0.8.0;

import "../../src/interfaces/IGate.sol";

interface IBundler3 {
    function initiator() external view returns (address);
}

interface IBundlerAdapter {
    function BUNDLER3() external view returns (IBundler3);
}

/// Example VaultV2 Gate with the following characteristics:
/// - It is a shares gate, i.e. it checks vault shares senders & receivers.
/// - It is a send assets gate, i.e. it checks users who deposit assets to the vault.
/// - It is a receive assets gate, i.e. it checks users who receive assets from the vault.
/// - It has a single whitelist for all permissions.
/// - It works with Bundler3.
///   To enable transfers to/from a Bundler3 adapter (for whitelisted users only), set isBundlerAdapter[bundlerAdapter]
/// to true.
///   Only trusted Bundler3 adapters should be added.
contract GateExample is IReceiveSharesGate, ISendSharesGate, IReceiveAssetsGate, ISendAssetsGate {
    address public owner;

    mapping(address => bool) public isBundlerAdapter;
    mapping(address => bool) public whitelisted;

    constructor(address _owner) {
        owner = _owner;
    }

    /* ERRORS */

    error Unauthorized();

    /* ROLES FUNCTIONS */

    /// @notice Set the owner of the gate.
    function setOwner(address newOwner) external {
        require(msg.sender == owner, Unauthorized());
        owner = newOwner;
    }

    /// @notice Set who is whitelisted.
    function setIsWhitelisted(address account, bool newIsWhitelisted) external {
        require(msg.sender == owner, Unauthorized());
        whitelisted[account] = newIsWhitelisted;
    }

    /// @notice Set who is allowed to handle shares and assets on behalf of another account.
    function setIsBundlerAdapter(address account, bool newIsBundlerAdapter) external {
        require(msg.sender == owner, Unauthorized());
        isBundlerAdapter[account] = newIsBundlerAdapter;
    }

    /* VIEW FUNCTIONS */

    /// @notice Check if `account` can send shares.
    function canSendShares(address account) external view returns (bool) {
        return whitelistedOrHandlingOnBehalf(account);
    }

    /// @notice Check if `account` can receive assets when a withdrawal is made.
    function canReceiveAssets(address account) external view returns (bool) {
        return whitelistedOrHandlingOnBehalf(account);
    }

    /// @notice Check if `account` can receive shares.
    function canReceiveShares(address account) external view returns (bool) {
        return whitelistedOrHandlingOnBehalf(account);
    }

    /// @notice Check if `account` can supply assets when a deposit is made.
    function canSendAssets(address account) external view returns (bool) {
        return whitelistedOrHandlingOnBehalf(account);
    }

    /* INTERNAL FUNCTIONS */

    function whitelistedOrHandlingOnBehalf(address account) internal view returns (bool) {
        return whitelisted[account]
            || (isBundlerAdapter[account] && whitelisted[IBundlerAdapter(account).BUNDLER3().initiator()]);
    }
}
