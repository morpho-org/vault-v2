// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import "../interfaces/IGate.sol";

interface IBundler3 {
    function initiator() external view returns (address);
}

interface IAdapter {
    function BUNDLER3() external view returns (IBundler3);
}

contract Gate is IGate {
    address public owner;

    mapping(address => bool) public isBundlerAdapter;
    mapping(address => bool) internal _canSendShares;
    mapping(address => bool) internal _canReceiveShares;
    mapping(address => bool) internal _canSupplyAssets;
    mapping(address => bool) internal _canWithdrawAssets;

    constructor(address _owner) {
        owner = _owner;
    }

    /* EVENTS */

    event Handling(address indexed handlingSetter, address indexed handler, address indexed onBehalf);

    /* ERRORS */

    error Unauthorized();
    error AlreadyHandling();

    /* ROLES FUNCTION */

    /// @notice Set the owner of the gate.
    function setOwner(address newOwner) external {
        require(msg.sender == owner, Unauthorized());
        owner = newOwner;
    }

    /// @notice Set who is allowed to send and receive shares.
    function setCanUseShares(address account, bool newCanSendShares, bool newCanReceiveShares) external {
        require(msg.sender == owner, Unauthorized());
        _canSendShares[account] = newCanSendShares;
        _canReceiveShares[account] = newCanReceiveShares;
    }

    /// @notice Set who is allowed to supply and withdraw assets.
    function setCanUseAssets(address account, bool newCanSupplyAssets, bool newCanWithdrawAssets) external {
        require(msg.sender == owner, Unauthorized());
        _canSupplyAssets[account] = newCanSupplyAssets;
        _canWithdrawAssets[account] = newCanWithdrawAssets;
    }

    /// @notice Set who is allowed to handle shares and assets on behalf of another account.
    function setIsBundlerAdapter(address account, bool newIsBundlerAdapter) external {
        require(msg.sender == owner, Unauthorized());
        isBundlerAdapter[account] = newIsBundlerAdapter;
    }

    /* VIEW FUNCTIONS */

    /// @notice Check if `account` can currently send shares.
    function canSendShares(address account) external view returns (bool) {
        return canDo(_canSendShares, account);
    }

    /// @notice Check if `account` can currently receive shares.
    function canReceiveShares(address account) external view returns (bool) {
        return canDo(_canReceiveShares, account);
    }

    /// @notice Check if `account` can currently supply assets.
    function canSupplyAssets(address account) external view returns (bool) {
        return canDo(_canSupplyAssets, account);
    }

    /// @notice Check if `account` can currently withdraw assets.
    function canWithdrawAssets(address account) external view returns (bool) {
        return canDo(_canWithdrawAssets, account);
    }

    /* INTERNAL FUNCTIONS */

    function canDo(mapping(address => bool) storage allowed, address account) internal view returns (bool) {
        return allowed[account] || (isBundlerAdapter[account] && allowed[IAdapter(account).BUNDLER3().initiator()]);
    }
}
