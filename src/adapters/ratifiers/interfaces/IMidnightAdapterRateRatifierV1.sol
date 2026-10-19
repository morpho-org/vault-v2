// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Morpho Association
pragma solidity >=0.5.0;

import {IRatifier} from "../../../../lib/midnight/src/interfaces/IRatifier.sol";

struct Ratification {
    bool isRootRatified;
    uint128 rootNonce;
}

/// @dev keccak256("EIP712Domain(uint256 chainId,address verifyingContract)").
bytes32 constant EIP712_DOMAIN_TYPEHASH = 0x47e79534a245952e8b16893a336b85a3d9ea9fa8c573f3d803afb92a79469218;

interface IMidnightAdapterRateRatifierV1 is IRatifier {
    /// ERRORS ///
    error DeadlineExpired();
    error InvalidNonce();
    error InvalidProof();
    error InvalidSignature();
    error NotRatified();
    error RatifiedStatusChanged();
    error Unauthorized();
    error UnauthorizedTaker();
    error WorsePrice();

    /// EVENTS ///
    event SetIsRootRatified(
        address caller, address indexed onBehalf, address indexed maker, bytes32 indexed root, bool newIsRootRatified
    );
    event SetIsRootRatifiedWithSig(
        address caller,
        address indexed signer,
        address indexed maker,
        bytes32 indexed root,
        uint256 height,
        bool newIsRootRatified,
        uint128 signatureNonce,
        uint128 previousNonce
    );

    function setIsRootRatified(address maker, bytes32 root, address onBehalf, bool newIsRootRatified)
        external
        returns (bytes32);

    function setIsRootRatifiedWithSig(
        address maker,
        bytes32 root,
        uint256 height,
        bool newIsRootRatified,
        uint128 nonce,
        uint256 deadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external returns (bytes32);

    /// GETTERS ///
    function DOMAIN_SEPARATOR() external view returns (bytes32);

    function isRootRatified(address maker, bytes32 root) external view returns (bool);
    function rootNonce(address maker, bytes32 root) external view returns (uint128);

    /// STORAGE GETTERS ///
    function ratification(address maker, bytes32 root) external view returns (bool isRootRatified, uint128 rootNonce);
}
