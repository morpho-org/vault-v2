// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Morpho Association
pragma solidity 0.8.28;

import {
    IWhitelistSendAssetsGate,
    IIntermediary,
    SET_IS_WHITELISTED_TYPEHASH
} from "./interfaces/IWhitelistSendAssetsGate.sol";
import {DOMAIN_TYPEHASH} from "../libraries/ConstantsLib.sol";

/// @dev Using this gate allows to restrict who the funds are initially owned by in a vault's deposits/mints.
/// @dev As with any send assets gate, nothing prevents whitelisted accounts from using a non whitelisted account's
/// funds.
/// @dev If account is registered as a trusted intermediary, IIntermediary(account).initiator() is checked for
/// whitelisted status instead of account itself. Thus the intermediary should only deposit and mint using assets
/// initially owned by its current initiator.
/// @dev No-ops are allowed.
/// @dev Zero checks are not systematically performed.
contract WhitelistSendAssetsGate is IWhitelistSendAssetsGate {
    address public roleSetter;
    address public whitelister;
    mapping(address => uint256) public nonces;
    mapping(address => bool) public isWhitelisted;
    mapping(address => bool) public isIntermediary;

    constructor(address _roleSetter) {
        roleSetter = _roleSetter;
        emit Constructor(_roleSetter);
    }

    /// @dev Useful for EOAs to batch privileged calls.
    /// @dev Does not return anything, because accounts who would use the return data would be contracts, which can do
    /// the multicall themselves.
    function multicall(bytes[] calldata data) external {
        for (uint256 i = 0; i < data.length; i++) {
            (bool success, bytes memory returnData) = address(this).delegatecall(data[i]);
            if (!success) {
                assembly ("memory-safe") {
                    revert(add(32, returnData), mload(returnData))
                }
            }
        }
    }

    /// @dev Reverts if isIntermediary[account] but account reverts on initiator().
    function canSendAssets(address account) external view returns (bool) {
        return isWhitelisted[isIntermediary[account] ? IIntermediary(account).initiator() : account];
    }

    function setRoleSetter(address newRoleSetter) external {
        require(msg.sender == roleSetter, NotRoleSetter());
        roleSetter = newRoleSetter;
        emit SetRoleSetter(newRoleSetter);
    }

    function setWhitelister(address newWhitelister) external {
        require(msg.sender == roleSetter, NotRoleSetter());
        whitelister = newWhitelister;
        emit SetWhitelister(newWhitelister);
    }

    function setIsWhitelisted(address account, bool newIsWhitelisted) external {
        require(msg.sender == whitelister, NotWhitelister());
        isWhitelisted[account] = newIsWhitelisted;
        emit SetIsWhitelisted(account, newIsWhitelisted);
    }

    function setIsIntermediary(address intermediary, bool newIsIntermediary) external {
        require(msg.sender == whitelister, NotWhitelister());
        isIntermediary[intermediary] = newIsIntermediary;
        emit SetIsIntermediary(intermediary, newIsIntermediary);
    }

    /// @dev Signature malleability is not explicitly prevented but it is not a problem thanks to the nonce.
    /// @dev Allows to batch setIsWhitelisted with the deposit, without requiring a transaction from the whitelister.
    function setIsWhitelistedWithSig(
        address account,
        bool newIsWhitelisted,
        uint256 deadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external {
        require(deadline >= block.timestamp, DeadlineExpired());
        bytes32 hashStruct =
            keccak256(abi.encode(SET_IS_WHITELISTED_TYPEHASH, account, newIsWhitelisted, nonces[account]++, deadline));
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", DOMAIN_SEPARATOR(), hashStruct));
        address recovered = ecrecover(digest, v, r, s);
        require(recovered != address(0) && recovered == whitelister, InvalidSigner());
        isWhitelisted[account] = newIsWhitelisted;
        emit SetIsWhitelistedWithSig(account, newIsWhitelisted);
    }

    /// forge-lint: disable-next-item(mixed-case-function)
    function DOMAIN_SEPARATOR() public view returns (bytes32) {
        return keccak256(abi.encode(DOMAIN_TYPEHASH, block.chainid, address(this)));
    }
}
