// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Morpho Association

using Utils as Utils;

methods {
    function isSentinel(address) external returns (bool) envfree;
    function executableAt(bytes) external returns (uint256) envfree;
    function absoluteCap(bytes32) external returns (uint256) envfree;
    function relativeCap(bytes32) external returns (uint256) envfree;
}

// Check that a sentinel can always revoke some pending data.
rule sentinelCanRevoke(env e, bytes data) {
    require executableAt(data) != 0, "assume that data is pending";
    require isSentinel(e.msg.sender), "setup call to be performed by a sentinel";
    require e.msg.value == 0, "setup call to have no ETH value";
    revoke@withrevert(e, data);
    assert !lastReverted;

    assert executableAt(data) == 0;
}

// Check that a sentinel can always decrease the absolute cap.
rule sentinelCanDecreaseAbsoluteCap(env e, bytes idData, uint256 newAbsoluteCap) {
    require newAbsoluteCap <= absoluteCap(keccak256(idData)), "setup call to have a newAbsoluteCap <= absoluteCap";
    require isSentinel(e.msg.sender), "setup call to be performed by a sentinel";
    require e.msg.value == 0, "setup call to have no ETH value";
    decreaseAbsoluteCap@withrevert(e, idData, newAbsoluteCap);
    assert !lastReverted;

    assert absoluteCap(keccak256(idData)) == newAbsoluteCap;
}

// Check that a sentinel can always decrease the relative cap.
rule sentinelCanDecreaseRelativeCap(env e, bytes idData, uint256 newRelativeCap) {
    require newRelativeCap <= relativeCap(keccak256(idData)), "setup call to have a newRelativeCap <= relativeCap";
    require isSentinel(e.msg.sender), "setup call to be performed by a sentinel";
    require e.msg.value == 0, "setup call to have no ETH value";
    decreaseRelativeCap@withrevert(e, idData, newRelativeCap);
    assert !lastReverted;

    assert relativeCap(keccak256(idData)) == newRelativeCap;
}
