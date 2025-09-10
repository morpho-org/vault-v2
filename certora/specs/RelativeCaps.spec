// Spdx-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Morpho Association

using Utils as Utils;

methods {
    function multicall(bytes[]) external => HAVOC_ALL DELETE;
    function deallocateInternal(address, bytes memory, uint256) internal returns (bytes32[] memory) => deallocateInternalSummary();
    function Utils.wad() external returns uint256 envfree;
}

persistent ghost bool deallocateInternalNotCalled {
    init_state axiom deallocateInternalNotCalled;
}

function deallocateInternalSummary() returns (bytes32[]) {
    deallocateInternalNotCalled = false;

    bytes32[] ids;
    uint i;
    havoc currentContract.caps[ids[i]].allocation assuming i < ids.length ;

    return ids;
}

// Check that allocation are within relative caps limit assuming no deallocation.
rule relativeCapValidity(env e, method f, calldataarg args) filtered {
    f -> f.selector != sig:decreaseRelativeCap(bytes,uint256).selector
} {
    bytes32 id;

    require currentContract.caps[id].relativeCap < Utils.wad() && deallocateInternalNotCalled =>
    currentContract.caps[id].allocation <= (currentContract.firstTotalAssets * currentContract.caps[id].relativeCap) / Utils.wad();

    f(e, args);

    assert currentContract.caps[id].relativeCap < Utils.wad() && deallocateInternalNotCalled =>
    currentContract.caps[id].allocation <= (currentContract.firstTotalAssets * currentContract.caps[id].relativeCap) / Utils.wad();
}
