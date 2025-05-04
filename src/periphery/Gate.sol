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
    mapping(address => bool) internal _canUseShares;
    mapping(address => bool) internal _canUseAssets;

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
    function setCanUseShares(address account, bool newCanUseShares) external {
        require(msg.sender == owner, Unauthorized());
        _canUseShares[account] = newCanUseShares;
    }

    /// @notice Set who is allowed to supply and withdraw assets.
    function setCanUseAssets(address account, bool newCanUseAssets) external {
        require(msg.sender == owner, Unauthorized());
        _canUseAssets[account] = newCanUseAssets;
    }

    /// @notice Set who is allowed to handle shares and assets on behalf of another account.
    function setIsBundlerAdapter(address account, bool newIsBundlerAdapter) external {
        require(msg.sender == owner, Unauthorized());
        isBundlerAdapter[account] = newIsBundlerAdapter;
    }

    /* VIEW FUNCTIONS */

    /// @notice Check if `account` can currently send and receive shares.
    function canUseShares(address account) external view returns (bool) {
        return _canUseShares[account]
            || (isBundlerAdapter[account] && _canUseShares[IAdapter(account).BUNDLER3().initiator()]);
    }

    /// @notice Check if `account` can currently supply and withdraw assets.
    function canUseAssets(address account) external view returns (bool) {
        return _canUseAssets[account]
            || (isBundlerAdapter[account] && _canUseAssets[IAdapter(account).BUNDLER3().initiator()]);
    }
}
