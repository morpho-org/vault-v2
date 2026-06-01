// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Morpho Association
pragma solidity >=0.5.0;

import {IReceiveSharesGate, ISendAssetsGate} from "../../interfaces/IGate.sol";

bytes32 constant SET_IS_WHITELISTED_TYPEHASH =
    keccak256("SetIsWhitelisted(address[] accounts,bool[] newIsWhitelisteds,uint256 nonce,uint256 deadline)");

interface IIntermediary {
    function initiator() external view returns (address);
}

/// @dev Entry-only gate: implements `canSendAssets` (deposit caller) and `canReceiveShares` (share recipient).
/// The exit-side gates (`canSendShares`, `canReceiveAssets`) are intentionally not exposed, so the whitelister
/// can never prevent an existing share holder from redeeming or being paid out.
interface IWhitelistedEntryGate is IReceiveSharesGate, ISendAssetsGate {
    /* EVENTS */

    event Constructor(address indexed whitelister);
    event SetWhitelister(address indexed newWhitelister);
    event SetIsWhitelisted(address indexed account, bool newIsWhitelisted);
    event SetIsIntermediary(address indexed intermediary, bool isIntermediary);

    /* ERRORS */

    error NotWhitelister();
    error PermitDeadlineExpired();
    error InvalidSigner();
    error LengthMismatch();

    /* FUNCTIONS */

    function whitelister() external view returns (address);
    function nonce() external view returns (uint256);
    function isIntermediary(address account) external view returns (bool);
    function isWhitelisted(address account) external view returns (bool);
    function isAllowed(address account) external view returns (bool);
    function setWhitelister(address newWhitelister) external;
    function setIsWhitelisted(address[] calldata accounts, bool[] calldata newIsWhitelisteds) external;
    function setIsIntermediary(address intermediary, bool newIsIntermediary) external;
    function setIsWhitelistedWithSig(
        address[] calldata accounts,
        bool[] calldata newIsWhitelisteds,
        uint256 deadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external;
    function DOMAIN_SEPARATOR() external view returns (bytes32);
}
