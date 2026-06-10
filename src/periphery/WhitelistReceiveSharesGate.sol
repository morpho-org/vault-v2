// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Morpho Association
pragma solidity 0.8.28;

import {IWhitelistReceiveSharesGate, SET_IS_WHITELISTED_TYPEHASH} from "./interfaces/IWhitelistReceiveSharesGate.sol";
import {DOMAIN_TYPEHASH} from "../libraries/ConstantsLib.sol";

/// @dev Using this gate allows to restrict who can own shares of a vault.
/// @dev As with any receive shares gates, a whitelisted account could own shares to let other accounts access the
/// vault's payoff.
/// @dev CRITICAL NOTE: if a depositor transfers their shares (typically to deposit them on a DeFi protocol), they might
/// not be able to get their shares back (typically to withdraw them) if they get un-whitelisted afterwards.
/// @dev No-ops are allowed.
/// @dev Zero checks are not systematically performed.
contract WhitelistReceiveSharesGate is IWhitelistReceiveSharesGate {
    address public whitelister;
    mapping(address => uint256) public nonces;
    mapping(address => bool) public isWhitelisted;

    constructor(address _whitelister) {
        whitelister = _whitelister;
        emit Constructor(_whitelister);
    }

    /// @dev Useful for EOAs to batch admin calls.
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

    function canReceiveShares(address account) external view returns (bool) {
        return isWhitelisted[account];
    }

    function setWhitelister(address newWhitelister) external {
        require(msg.sender == whitelister, NotWhitelister());
        whitelister = newWhitelister;
        emit SetWhitelister(newWhitelister);
    }

    function setIsWhitelisted(address account, bool newIsWhitelisted) external {
        require(msg.sender == whitelister, NotWhitelister());
        isWhitelisted[account] = newIsWhitelisted;
        emit SetIsWhitelisted(account, newIsWhitelisted);
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
