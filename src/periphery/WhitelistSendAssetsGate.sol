// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Morpho Association
pragma solidity 0.8.28;

import {
    IWhitelistSendAssetsGate,
    IIntermediary,
    SET_IS_WHITELISTED_TYPEHASH
} from "./interfaces/IWhitelistSendAssetsGate.sol";
import {DOMAIN_TYPEHASH} from "../libraries/ConstantsLib.sol";

/// @dev If `account` is registered as a trusted intermediary, IIntermediary(account).initiator() is checked instead.
contract WhitelistSendAssetsGate is IWhitelistSendAssetsGate {
    address public whitelister;
    mapping(address => uint256) public nonces;
    mapping(address => bool) public isIntermediary;
    mapping(address => bool) public isWhitelisted;

    constructor(address _whitelister) {
        whitelister = _whitelister;
        emit Constructor(_whitelister);
    }

    function canSendAssets(address account) external view returns (bool) {
        if (isIntermediary[account]) account = IIntermediary(account).initiator();
        return isWhitelisted[account];
    }

    function setWhitelister(address newWhitelister) external {
        require(msg.sender == whitelister, NotWhitelister());
        whitelister = newWhitelister;
        emit SetWhitelister(newWhitelister);
    }

    function setIsWhitelisted(address account, bool whitelisted) external {
        require(msg.sender == whitelister, NotWhitelister());
        isWhitelisted[account] = whitelisted;
        emit SetIsWhitelisted(account, whitelisted);
    }

    function setIsIntermediary(address intermediary, bool newIsIntermediary) external {
        require(msg.sender == whitelister, NotWhitelister());
        isIntermediary[intermediary] = newIsIntermediary;
        emit SetIsIntermediary(intermediary, newIsIntermediary);
    }

    /// @dev Signature malleability is not explicitly prevented but it is not a problem thanks to the nonce.
    function setIsWhitelistedWithSig(address account, bool whitelisted, uint256 deadline, uint8 v, bytes32 r, bytes32 s)
        external
    {
        require(deadline >= block.timestamp, PermitDeadlineExpired());
        bytes32 hashStruct =
            keccak256(abi.encode(SET_IS_WHITELISTED_TYPEHASH, account, whitelisted, nonces[account]++, deadline));
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", DOMAIN_SEPARATOR(), hashStruct));
        address recovered = ecrecover(digest, v, r, s);
        require(recovered != address(0) && recovered == whitelister, InvalidSigner());
        isWhitelisted[account] = whitelisted;
        emit SetIsWhitelisted(account, whitelisted);
    }

    /// forge-lint: disable-next-item(mixed-case-function)
    function DOMAIN_SEPARATOR() public view returns (bytes32) {
        return keccak256(abi.encode(DOMAIN_TYPEHASH, block.chainid, address(this)));
    }
}
