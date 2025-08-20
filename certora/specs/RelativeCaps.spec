// Spdx-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Morpho Association

using Utils as Utils;

methods {
    function multicall(bytes[]) external => NONDET DELETE;
    function deallocateInternal(address, bytes memory, uint256) internal returns (bytes32[] memory) => deallocateInternalSummary();
    function Utils.wad() external returns uint256 envfree;
}

// Ghost copy of firstTotalAssets that persists after transient storage reset.
persistent ghost uint256 gFirstTotalAssets {
    init_state axiom gFirstTotalAssets == 0;
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

hook Tload uint256 value currentContract.firstTotalAssets {
    require gFirstTotalAssets == value;
}

hook Tstore currentContract.firstTotalAssets uint256 value (uint256 _) {
    gFirstTotalAssets = value;
}

// Check that allocation are within relative caps limit assuming no deallocation.
invariant relativeCapValidity(bytes32 id)
    currentContract.caps[id].relativeCap < Utils.wad() && deallocateInternalNotCalled =>
    currentContract.caps[id].allocation <= (gFirstTotalAssets * currentContract.caps[id].relativeCap) / Utils.wad()
    filtered {
      f -> f.selector != sig:decreaseRelativeCap(bytes,uint256).selector
    }
