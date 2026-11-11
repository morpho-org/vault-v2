// SPDX-License-Identifier: MIT
// Copyright (c) 2025 Morpho Association

// Midnight and the enter gate contracts are in the scene only to name the selectors of the ignored static calls. They are not linked, so the calls of the adapter stay unresolved.
using Midnight as Midnight;
using VaultV2CompatibleEnterGateFactory as VaultV2CompatibleEnterGateFactory;
using VaultV2CompatibleEnterGate as VaultV2CompatibleEnterGate;

methods {
    function multicall(bytes[]) external => HAVOC_ALL DELETE;
}

// True when at least one slot was written.
persistent ghost bool storageChanged;

// True when at least one STATICCALL is executed after a storage change.
persistent ghost bool staticCallAfterStore;

// True when at least one slot is changed after a STATICCALL is executed after a storage change.
persistent ghost bool staticCallUnsafe;

hook ALL_SSTORE(uint _, uint _) {
    storageChanged = true;
    if (staticCallAfterStore) {
        staticCallUnsafe = true;
    }
}

hook ALL_TSTORE(uint _, uint _) {
    storageChanged = true;
    if (staticCallAfterStore) {
        staticCallUnsafe = true;
    }
}

// These five static calls are assumed to not re-enter the adapter.
// Midnight's updatePositionView, liquidationLocked and lossFactor read Midnight's own state and make no call.
// onSell reads the three of them between the store of the sold market and the stores of the reduced rates.
// A self-funded onBuy reads liquidationLocked and updatePositionView between the stores of the bought market and the store of the funding market.
// forceDeallocate reads updatePositionView between the writes of inForceDeallocate and admitting and the store of the net credit.
// The enter gate factory's isCreated and the enter gate's canAdmit: onBuy reads them for a new market between the stores of this market and the reset of the in-progress buy.
hook STATICCALL(uint256 _, address _, uint256 _, uint256 _, uint256 _, uint256 _) uint256 _ {
    if (
        storageChanged
            && selector != sig:Midnight.updatePositionView(Midnight.Market, bytes32, address).selector
            && selector != sig:Midnight.liquidationLocked(bytes32, address).selector
            && selector != sig:Midnight.lossFactor(bytes32).selector
            && selector != sig:VaultV2CompatibleEnterGateFactory.isCreated(address).selector
            && selector != sig:VaultV2CompatibleEnterGate.canAdmit(address).selector
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
