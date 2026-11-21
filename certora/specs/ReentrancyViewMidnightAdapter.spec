// SPDX-License-Identifier: MIT
// Copyright (c) 2025 Morpho Association

import "../helpers/UtilityMidnightAdapter.spec";
import "../helpers/UtilityLinkedMidnight.spec";

// The conf links the adapter's midnight to the Midnight contract. When the adapter calls Midnight, the prover executes Midnight's code. The hooks below trigger on the instructions of Midnight too.
// VaultV2CompatibleEnterGateFactory, VaultV2CompatibleEnterGate and Oracle are in the scene only to name the selectors of the ignored static calls. They are not linked, so the static calls to the enter gate factory, to the enter gates and to the oracles stay unresolved.
using Midnight as Midnight;
using VaultV2CompatibleEnterGateFactory as VaultV2CompatibleEnterGateFactory;
using VaultV2CompatibleEnterGate as VaultV2CompatibleEnterGate;
using Oracle as Oracle;

methods {
    function multicall(bytes[]) external => HAVOC_ALL DELETE;

    // msb makes no static call and does not write the storage of the adapter. NONDET replaces it with an arbitrary result, which makes the proof faster.
    // It is not in UtilityLinkedMidnight.spec, because isHealthy calls it, and ReentrancyMidnightAdapter.spec replaces isHealthy itself.
    function UtilsLib.msb(uint128) internal returns (uint256) => NONDET;
}

// True when at least one slot was written.
persistent ghost bool storageChanged;

// True when at least one STATICCALL is executed after a storage change.
persistent ghost bool staticCallAfterStore;

// True when at least one slot is changed after a STATICCALL is executed after a storage change.
persistent ghost bool staticCallUnsafe;

// The prover also executes Midnight's code, which writes the storage of Midnight. The check on executingContract keeps only the writes that the adapter makes.
hook ALL_SSTORE(uint _, uint _) {
    if (executingContract == currentContract) {
        storageChanged = true;
        if (staticCallAfterStore) {
            staticCallUnsafe = true;
        }
    }
}

hook ALL_TSTORE(uint _, uint _) {
    if (executingContract == currentContract) {
        storageChanged = true;
        if (staticCallAfterStore) {
            staticCallUnsafe = true;
        }
    }
}

// The hook triggers on each STATICCALL that the adapter or Midnight executes. It does not set staticCallAfterStore in three cases.
// 1. The target is Midnight. The prover executes Midnight's code for this static call, and the hook triggers on each STATICCALL in this code.
// 2. The target is the adapter. This is Midnight's take calling isRatified. The prover does not execute it. It is between two writes of the adapter only in forceDeallocate, where it returns as soon as it reads inForceDeallocate.
// 3. The static call is one of these four, which are assumed to not re-enter the adapter.
// The enter gate factory's isCreated and the enter gate's canAdmit: sound because they are assumed to not re-enter.
// Needed because onBuy reads them for a new market between the stores of this market and the reset of the in-progress buy.
// The enter gate's canIncreaseCredit and the oracles' price: sound because they are assumed to not re-enter.
// why do we need it:
// - forceDeallocate writes inForceDeallocate and admitting, then calls Midnight's take, then stores the net credit. During this take, Midnight calls canIncreaseCredit, and it calls price when the adapter has debt.
hook STATICCALL(uint256 _, address addr, uint256 _, uint256 _, uint256 _, uint256 _) uint256 _ {
    if (
        storageChanged
            && addr != Midnight
            && addr != currentContract
            && selector != sig:VaultV2CompatibleEnterGateFactory.isCreated(address).selector
            && selector != sig:VaultV2CompatibleEnterGate.canAdmit(address).selector
            && selector != sig:VaultV2CompatibleEnterGate.canIncreaseCredit(address).selector
            && selector != sig:Oracle.price().selector
    ) {
        staticCallAfterStore = true;
    }
}

// Check that static calls are either before the first store or after the last store.
rule reentrancyViewSafe(method f, env e, calldataarg data) {
    require(!storageChanged && !staticCallAfterStore && !staticCallUnsafe, "set up the initial ghost state");
    f(e, data);
    assert !staticCallUnsafe;
}
