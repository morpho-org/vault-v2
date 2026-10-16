// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Morpho Association
pragma solidity >=0.5.0;

import {IRatifier} from "lib/midnight/src/interfaces/IRatifier.sol";

interface IMidnightAdapterRatifiersV1Common is IRatifier {
    /// @dev onBehalf must be an allocator, or a sentinel when unratifying. It must authorize the caller on Midnight unless it is the caller.
    function setIsRootRatified(address maker, bytes32 root, bool newIsRootRatified, address onBehalf)
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

    function isRootRatified(address maker, bytes32 root) external view returns (bool);
    function rootNonce(address maker, bytes32 root) external view returns (uint128);
}
