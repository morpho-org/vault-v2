// SPDX-License-Identifier: MIT
// Copyright (c) 2025 Morpho Association

methods {
    // durationAllocations loops over marketIds and, with optimistic_loop, paths with more than loop_iter iterations are pruned, so without this summary onBuy would only be checked on short market lists, while the invariants depend on the list's length.
    // The ids summary is needed, because otherwise the prover wouldn't resolve Midnight's calls in the functions that call ids.
    // It's fine if other loops are pruned: realAssets loops over marketIds but writes nothing, and the loops over durations don't write the adapter's state, so a path with more iterations has a counterpart with fewer iterations and the same market list.
    function durationAllocations(uint256 length) internal returns (uint256[] memory) => arbitraryAllocations(length);
    function ids(MidnightAdapter.Market memory) internal returns (bytes32[] memory) => arbitraryIds();
}

function arbitraryIds() returns bytes32[] {
    bytes32[] idsArray;
    return idsArray;
}

function arbitraryAllocations(uint256 length) returns uint256[] {
    uint256[] allocations;
    require allocations.length == length, "durationAllocations returns length allocations";
    return allocations;
}
