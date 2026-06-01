// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Morpho Association
pragma solidity 0.8.28;

import {
    IWhitelistedEntryGate,
    IIntermediary,
    SET_IS_WHITELISTED_TYPEHASH
} from "./interfaces/IWhitelistedEntryGate.sol";
import {DOMAIN_TYPEHASH} from "../libraries/ConstantsLib.sol";

/// @dev Entry-only allowlist gate for VaultV2. Plugs into the `sendAssetsGate` slot (gates deposit callers) and
/// the `receiveSharesGate` slot (gates share recipients on deposits and transfers). The two exit-path gate
/// methods (`canSendShares`, `canReceiveAssets`) are intentionally not implemented so that share holders can
/// always exit the vault regardless of whitelist state. If `account` is registered as a trusted intermediary,
/// IIntermediary(account).initiator() is checked instead.
contract WhitelistedEntryGate is IWhitelistedEntryGate {
    address public whitelister;
    uint256 public nonce;
    mapping(address => bool) public isIntermediary;
    mapping(address => bool) public isWhitelisted;

    constructor(address _whitelister) {
        whitelister = _whitelister;
        emit Constructor(_whitelister);
    }

    function canReceiveShares(address account) external view returns (bool) {
        return isAllowed(account);
    }

    function canSendAssets(address account) external view returns (bool) {
        return isAllowed(account);
    }

    function isAllowed(address account) public view returns (bool) {
        return isWhitelisted[isIntermediary[account] ? IIntermediary(account).initiator() : account];
    }

    function setWhitelister(address newWhitelister) external {
        require(msg.sender == whitelister, NotWhitelister());
        whitelister = newWhitelister;
        emit SetWhitelister(newWhitelister);
    }

    function setIsWhitelisted(address[] calldata accounts, bool[] calldata newIsWhitelisteds) external {
        require(msg.sender == whitelister, NotWhitelister());
        _setIsWhitelisted(accounts, newIsWhitelisteds);
    }

    function setIsIntermediary(address intermediary, bool newIsIntermediary) external {
        require(msg.sender == whitelister, NotWhitelister());
        isIntermediary[intermediary] = newIsIntermediary;
        emit SetIsIntermediary(intermediary, newIsIntermediary);
    }

    /// @dev Signature malleability is not explicitly prevented but it is not a problem thanks to the nonce.
    function setIsWhitelistedWithSig(
        address[] calldata accounts,
        bool[] calldata newIsWhitelisteds,
        uint256 deadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external {
        require(deadline >= block.timestamp, PermitDeadlineExpired());
        bytes32 hashStruct = keccak256(
            abi.encode(
                SET_IS_WHITELISTED_TYPEHASH, _hashAccounts(accounts), _hashBools(newIsWhitelisteds), nonce++, deadline
            )
        );
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", DOMAIN_SEPARATOR(), hashStruct));
        address recovered = ecrecover(digest, v, r, s);
        require(recovered != address(0) && recovered == whitelister, InvalidSigner());
        _setIsWhitelisted(accounts, newIsWhitelisteds);
    }

    /// forge-lint: disable-next-item(mixed-case-function)
    function DOMAIN_SEPARATOR() public view returns (bytes32) {
        return keccak256(abi.encode(DOMAIN_TYPEHASH, block.chainid, address(this)));
    }

    function _setIsWhitelisted(address[] calldata accounts, bool[] calldata newIsWhitelisteds) internal {
        require(accounts.length == newIsWhitelisteds.length, LengthMismatch());
        for (uint256 i; i < accounts.length; ++i) {
            isWhitelisted[accounts[i]] = newIsWhitelisteds[i];
            emit SetIsWhitelisted(accounts[i], newIsWhitelisteds[i]);
        }
    }

    /// @dev EIP-712 array hash: keccak256 of each element's atomic encoding (32 bytes), concatenated.
    function _hashAccounts(address[] calldata accounts) internal pure returns (bytes32) {
        bytes32[] memory padded = new bytes32[](accounts.length);
        for (uint256 i; i < accounts.length; ++i) {
            padded[i] = bytes32(uint256(uint160(accounts[i])));
        }
        return keccak256(abi.encodePacked(padded));
    }

    function _hashBools(bool[] calldata values) internal pure returns (bytes32) {
        bytes32[] memory padded = new bytes32[](values.length);
        for (uint256 i; i < values.length; ++i) {
            padded[i] = bytes32(uint256(values[i] ? 1 : 0));
        }
        return keccak256(abi.encodePacked(padded));
    }
}
