// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Morpho Association
pragma solidity >=0.5.0;

import {IReceiveSharesGate} from "../../interfaces/IGate.sol";

bytes32 constant SET_IS_WHITELISTED_TYPEHASH =
    keccak256("SetIsWhitelisted(address account,bool newIsWhitelisted,uint256 nonce,uint256 deadline)");

interface IWhitelistReceiveSharesGate is IReceiveSharesGate {
    /* EVENTS */

    event Constructor(address indexed roleSetter, address indexed whitelister);
    event SetRoleSetter(address indexed newRoleSetter);
    event SetWhitelister(address indexed newWhitelister);
    event SetIsWhitelisted(address indexed account, bool newIsWhitelisted);
    event SetIsWhitelistedWithSig(address indexed account, bool newIsWhitelisted);

    /* ERRORS */

    error NotRoleSetter();
    error NotWhitelister();
    error DeadlineExpired();
    error InvalidSigner();

    /* FUNCTIONS */

    function roleSetter() external view returns (address);
    function whitelister() external view returns (address);
    function nonces(address account) external view returns (uint256);
    function isWhitelisted(address account) external view returns (bool);
    function setRoleSetter(address newRoleSetter) external;
    function setWhitelister(address newWhitelister) external;
    function setIsWhitelisted(address account, bool newIsWhitelisted) external;
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
