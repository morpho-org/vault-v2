// SPDX-License-Identifier: MIT
// Copyright (c) 2025 Morpho Association

import "../helpers/UtilityMidnightAdapter.spec";
import "../helpers/UtilityLinkedMidnight.spec";

// The conf links the adapter's midnight to the Midnight contract. When the adapter calls Midnight, the prover executes Midnight's code. The hooks below trigger on the instructions of Midnight too.
// VaultV2, VaultV2CompatibleEnterGate and ERC20Mock are in the scene only to name the selectors of the ignored calls. They are not linked, so the calls to the vault, to the enter gates and to the loan token stay unresolved.
using VaultV2 as VaultV2;
using Midnight as Midnight;
using VaultV2CompatibleEnterGate as VaultV2CompatibleEnterGate;
using ERC20Mock as ERC20Mock;

methods {
    function multicall(bytes[]) external => HAVOC_ALL DELETE;

    // isHealthy and updatePositionView make no CALL and do not write the storage of the adapter. NONDET replaces each of them with an arbitrary result, which makes the proof faster.
    // They are not in UtilityLinkedMidnight.spec, because ReentrancyViewMidnightAdapter.spec needs the prover to execute them.
    function Midnight.isHealthy(Midnight.Market memory, bytes32, address) internal returns (bool) => NONDET;
    function Midnight.updatePositionView(Midnight.Market, bytes32, address) external returns (uint128, uint128, uint128) => NONDET;
}

// True when at least one slot was written.
persistent ghost bool storageChanged;

// True when at least one CALL is executed after a storage change.
persistent ghost bool hasCallAfterStore;

// True when at least one slot is changed after a CALL is executed after a storage change.
persistent ghost bool unsafeCall;

// The prover also executes Midnight's code, which writes the storage of Midnight. The check on executingContract keeps only the writes that the adapter makes.
hook ALL_SSTORE(uint _, uint _) {
    if (executingContract == currentContract) {
        storageChanged = true;
        if (hasCallAfterStore) {
            unsafeCall = true;
        }
    }
}

hook ALL_TSTORE(uint _, uint _) {
    if (executingContract == currentContract) {
        storageChanged = true;
        if (hasCallAfterStore) {
            unsafeCall = true;
        }
    }
}

// The hook triggers on each CALL that the adapter or Midnight executes. It does not set hasCallAfterStore in three cases.
// 1. The target is Midnight. The prover executes Midnight's code for this call, and the hook triggers on each CALL in this code.
// 2. The target is the adapter. This is Midnight calling onBuy or onSell. The prover executes the adapter's code for this call, and the hooks trigger on the writes and on the CALLs in this code.
// 3. The call is one of these four, which are assumed to not re-enter the adapter.
// accrueInterest: sound because it only makes static calls.
// Needed because onBuy calls it after it sets the in-progress buy and before it clears it.
// The loan token's transfer and transferFrom, and the enter gate's unadmit: sound because they are assumed to not re-enter.
// why do we need it:
// - Midnight's withdraw calls transfer. A self-funded onBuy calls withdraw after it stores the bought market and before it stores the net credit of the funding market.
// - forceDeallocate writes inForceDeallocate and admitting, then calls Midnight's take, then stores the net credit. During this take, Midnight calls transferFrom, and onBuy calls unadmit.
hook CALL(uint256 _, address addr, uint256 _, uint256 _, uint256 _, uint256 _, uint256 _) uint256 _ {
    if (
        storageChanged
            && addr != Midnight
            && addr != currentContract
            && selector != sig:VaultV2.accrueInterest().selector
            && selector != sig:ERC20Mock.transfer(address, uint256).selector
            && selector != sig:ERC20Mock.transferFrom(address, address, uint256).selector
            && selector != sig:VaultV2CompatibleEnterGate.unadmit().selector
    ) {
        hasCallAfterStore = true;
    }
}

// Check that calls are either before the first store or after the last store.
rule reentrancySafe(method f, env e, calldataarg data) {
    require(!storageChanged && !hasCallAfterStore && !unsafeCall, "set up the initial ghost state");
    f(e, data);
    assert !unsafeCall;
}
