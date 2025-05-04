// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import "../interfaces/IGate.sol";

contract Gate is IGate {
    address public owner;
    address public immutable VAULT;
    bytes32 public constant HANDLING_SLOT_PREFIX = keccak256("VaultV2 Gate Handling");

    mapping(address => bool) internal _canUseShares;
    mapping(address => bool) internal _canUseAssets;
    mapping(address => bool) public canHandle;
    mapping(address => bool) public canSetHandling;

    constructor(address _owner, address _vault) {
        owner = _owner;
        VAULT = _vault;
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
    function setCanHandle(address account, bool newCanHandle) external {
        require(msg.sender == owner, Unauthorized());
        canHandle[account] = newCanHandle;
    }

    /// @notice Set who is allowed to associate a handling with an account.
    function setCanSetHandling(address account, bool newCanSetSharesHandling) external {
        require(msg.sender == owner, Unauthorized());
        canSetHandling[account] = newCanSetSharesHandling;
    }

    /* HANDLING FUNCTIONS */

    /// @notice Transiently allow `handler` to handles shares and assets on behalf of `onBehalf`.
    function setHandling(address handlingSetter, address handler, address onBehalf) external {
        require(msg.sender == VAULT, Unauthorized());
        require(handlingSetter == onBehalf || canSetHandling[handlingSetter], Unauthorized());

        if (onBehalf != address(0)) {
            require(canHandle[handler], Unauthorized());
            require(_getHandling(handler) == address(0), AlreadyHandling());
        }

        emit Handling(handlingSetter, handler, onBehalf);
        _setHandling(handler, onBehalf);
    }

    /// @notice Check if `account` can currently send and receive shares.
    function canUseShares(address account) external view returns (bool) {
        return _canUseShares[account] || _canUseShares[_getHandling(account)];
    }

    /// @notice Check if `account` can currently supply and withdraw assets.
    function canUseAssets(address account) external view returns (bool) {
        return _canUseAssets[account] || _canUseAssets[_getHandling(account)];
    }

    function getHandling(address handler) external view returns (address) {
        return _getHandling(handler);
    }

    /* INTERNAL FUNCTIONS */

    function _getHandling(address handler) internal view returns (address handled) {
        bytes32 slot = keccak256(abi.encodePacked(HANDLING_SLOT_PREFIX, handler));
        assembly {
            handled := tload(slot)
        }
    }

    function _setHandling(address handler, address handled) internal {
        bytes32 slot = keccak256(abi.encodePacked(HANDLING_SLOT_PREFIX, handler));
        assembly {
            tstore(slot, handled)
        }
    }
}
