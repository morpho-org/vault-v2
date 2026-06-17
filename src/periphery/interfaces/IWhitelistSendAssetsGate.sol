// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Morpho Association
pragma solidity >=0.5.0;

import {ISendAssetsGate} from "../../interfaces/IGate.sol";

bytes32 constant SET_IS_WHITELISTED_TYPEHASH =
    keccak256("SetIsWhitelisted(address account,bool newIsWhitelisted,uint256 nonce,uint256 deadline)");

interface IIntermediary {
    function initiator() external view returns (address);
}

interface IWhitelistSendAssetsGate is ISendAssetsGate {
    /* EVENTS */

    event Constructor(address indexed roleSetter);
    event SetRoleSetter(address indexed newRoleSetter);
    event SetIsWhitelister(address indexed whitelister, bool newIsWhitelister);
    event SetIsWhitelisted(address indexed whitelister, address indexed account, bool newIsWhitelisted);
    event SetIsWhitelistedWithSig(address indexed whitelister, address indexed account, bool newIsWhitelisted);
    event SetIsIntermediary(address indexed whitelister, address indexed intermediary, bool newIsIntermediary);

    /* ERRORS */

    error NotRoleSetter();
    error NotWhitelister();
    error DeadlineExpired();
    error InvalidSigner();

    /* FUNCTIONS */

    function roleSetter() external view returns (address);
    function isWhitelister(address account) external view returns (bool);
    function nonces(address account) external view returns (uint256);
    function isWhitelisted(address account) external view returns (bool);
    function isIntermediary(address account) external view returns (bool);
    function setRoleSetter(address newRoleSetter) external;
    function setIsWhitelister(address account, bool newIsWhitelister) external;
    function setIsWhitelisted(address account, bool newIsWhitelisted) external;
    function setIsIntermediary(address intermediary, bool newIsIntermediary) external;
    function setIsWhitelistedWithSig(
        address account,
        bool newIsWhitelisted,
        uint256 deadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external;
    function DOMAIN_SEPARATOR() external view returns (bytes32);
    function multicall(bytes[] calldata data) external;
}
