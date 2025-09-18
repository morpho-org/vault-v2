// Spdx-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Morpho Association

using Utils as Utils;

methods {
    function multicall(bytes[]) external => HAVOC_ALL DELETE;
    function deallocateInternal(address, bytes memory, uint256) internal returns (bytes32[] memory) => deallocateInternalSummary();
    function Utils.wad() external returns (uint256) envfree;
}

persistent ghost bool deallocateInternalCalled;

function deallocateInternalSummary() returns (bytes32[]) {
    deallocateInternalCalled = true;

    bytes32[] ids;
    uint i;
    havoc currentContract.caps[ids[i]].allocation assuming i < ids.length;

    return ids;
}

// Check that allocation are within relative caps limit assuming no deallocation and no relative cap decrease.
rule relativeCapValidity(env e, method f, calldataarg args)
filtered { f -> f.selector != sig:decreaseRelativeCap(bytes, uint256).selector } {
    bytes32 id;

    require currentContract.caps[id].relativeCap < Utils.wad() =>
    currentContract.caps[id].allocation <= (currentContract.firstTotalAssets * currentContract.caps[id].relativeCap) / Utils.wad();

    f(e, args);

    require !deallocateInternalCalled;

    // Note that firstTotalAssets is not reset after f, as functions calls are not isolated in different transactions in CVL.
    assert currentContract.caps[id].relativeCap < Utils.wad() =>
    currentContract.caps[id].allocation <= (currentContract.firstTotalAssets * currentContract.caps[id].relativeCap) / Utils.wad();
}
