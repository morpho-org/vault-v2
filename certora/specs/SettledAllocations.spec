// SPDX-License-Identifier: MIT
// Copyright (c) 2025 Morpho Association

methods {
    function multicall(bytes[]) external => HAVOC_ALL DELETE;

    function _.allocate(bytes, uint256, bytes4, address) external => adapterUpdateSummary() expect(bytes32[], int256);
    function _.deallocate(bytes, uint256, bytes4, address) external => adapterUpdateSummary() expect(bytes32[], int256);
    function _.realAssets() external => NONDET;
}

// Ids returned by the last adapter allocate or deallocate.
persistent ghost mapping(uint256 => bytes32) returnedIds;

persistent ghost uint256 returnedIdsLength;

// Allocation change returned by the last adapter allocate or deallocate.
persistent ghost int256 returnedChange;

// Number of returned ids whose allocation the vault updated by the returned change, in order.
persistent ghost uint256 writtenIdsCount;

persistent ghost bool callWithPendingWrites;

// Whether the vault wrote an allocation other than the next returned id updated by the returned change.
persistent ghost bool unexpectedAllocationWrite;

hook Sstore caps[KEY bytes32 id].allocation uint256 newAllocation (uint256 oldAllocation) {
    require(oldAllocation <= 2 ^ 255 - 1, "see allocationIsInt256");
    if (writtenIdsCount < returnedIdsLength && id == returnedIds[writtenIdsCount] && newAllocation == oldAllocation + returnedChange) {
        writtenIdsCount = assert_uint256(writtenIdsCount + 1);
    } else {
        unexpectedAllocationWrite = true;
    }
}

function checkSettledAllocations() {
    if (writtenIdsCount != returnedIdsLength) {
        callWithPendingWrites = true;
    }
}

// The call to the adapter is checked here, before the returned ids are recorded.
function adapterUpdateSummary() returns (bytes32[], int256) {
    checkSettledAllocations();
    bytes32[] ids;
    int256 change;
    havoc returnedIds assuming forall uint256 i. i < ids.length => returnedIds@new[i] == ids[i];
    returnedIdsLength = ids.length;
    returnedChange = change;
    writtenIdsCount = 0;
    return (ids, change);
}

// Call hooks run after the call. This is the same as checking before it, because all calls are summarized and none writes the vault's storage.
// Because call hooks run after the call, the calls to the adapters' allocate (0x1eadd778) and deallocate (0x4e45f1ff) are skipped, and the check is done in the summary instead.
hook CALL(uint256 _, address _, uint256 _, uint256 _, uint256 _, uint256 _, uint256 _) uint256 _ {
    if (selector != 0x1eadd778 && selector != 0x4e45f1ff) {
        checkSettledAllocations();
    }
}

hook STATICCALL(uint256 _, address _, uint256 _, uint256 _, uint256 _, uint256 _) uint256 _ {
    checkSettledAllocations();
}

// Check that the vault updates the allocation of every id returned by an adapter by the returned change, in order, with no other allocation write, before making any external call, so that allocations are up to date whenever another contract runs. Also check that allocations are settled at the end, which justifies deleting multicall.
rule callsAreMadeWithSettledAllocations(method f, env e, calldataarg data) {
    require(returnedIdsLength == 0 && writtenIdsCount == 0 && !callWithPendingWrites && !unexpectedAllocationWrite, "set up the initial ghost state");
    f(e, data);
    assert !callWithPendingWrites;
    assert !unexpectedAllocationWrite;
    assert writtenIdsCount == returnedIdsLength;
}
