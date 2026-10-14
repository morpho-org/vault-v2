// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Morpho Association

using Utils as Utils;

methods {
    function Utils.maxForceDeallocatePenalty() external returns (uint256) envfree;

    function multicall(bytes[]) external => HAVOC_ALL DELETE;

    // Ignore changes done by accrueInterest; the state after this call is still valid even if it changed the state, as for the accrueInterest entry point.
    function accrueInterest() internal => NONDET;

    // The vault only calls transfer, transferFrom and balanceOf on the asset.
    function _.transfer(address to, uint256 amount) external => summaryTransfer(to, amount) expect(bool);
    function _.transferFrom(address from, address to, uint256 amount) external => summaryTransferFrom(from, to, amount) expect(bool);
    function _.balanceOf(address account) external => summaryBalanceOf(account) expect(uint256);
}

// Set by the transfer summaries, and reset by the CALL hook of the summarized call.
persistent ghost bool ignoredCall;

// Balance of the vault in the asset, used to show that the penalty withdrawal of forceDeallocate does not deallocate again.
ghost uint256 vaultBalance;

function summaryTransfer(address to, uint256 amount) returns bool {
    ignoredCall = true;
    require(vaultBalance >= amount, "the transfer reverts otherwise");
    vaultBalance = assert_uint256(vaultBalance - amount);
    if (to == currentContract) {
        vaultBalance = assert_uint256(vaultBalance + amount);
    }
    return true;
}

function summaryTransferFrom(address from, address to, uint256 amount) returns bool {
    ignoredCall = true;
    if (from == currentContract) {
        require(vaultBalance >= amount, "the transfer reverts otherwise");
        vaultBalance = assert_uint256(vaultBalance - amount);
    }
    if (to == currentContract) {
        require(vaultBalance + amount <= max_uint256, "the total supply of the asset fits in a uint256");
        vaultBalance = assert_uint256(vaultBalance + amount);
    }
    return true;
}

function summaryBalanceOf(address account) returns uint256 {
    if (account == currentContract) {
        return vaultBalance;
    }
    uint256 balance;
    return balance;
}

// True when at least one slot of the vault was written.
persistent ghost bool storageChanged;

// True when at least one CALL other than the asset's transfer and transferFrom is executed after a storage change.
persistent ghost bool hasCallAfterStore;

// True when at least one slot of the vault is changed after a CALL is executed after a storage change.
persistent ghost bool unsafeCall;

// True when at least one CALL other than the asset's transfer and transferFrom is executed.
persistent ghost bool hasCall;

// Number of writes to the vault's storage after a CALL other than the asset's transfer and transferFrom.
persistent ghost mathint storesAfterCall;

// Number of writes to caps allocations after a CALL other than the asset's transfer and transferFrom.
persistent ghost mathint allocationStoresAfterCall;

hook ALL_SSTORE(uint _, uint _) {
    if (executingContract == currentContract) {
        storageChanged = true;
        if (hasCallAfterStore) {
            unsafeCall = true;
        }
        if (hasCall) {
            storesAfterCall = storesAfterCall + 1;
        }
    }
}

hook ALL_TSTORE(uint _, uint _) {
    if (executingContract == currentContract) {
        storageChanged = true;
        if (hasCallAfterStore) {
            unsafeCall = true;
        }
        if (hasCall) {
            storesAfterCall = storesAfterCall + 1;
        }
    }
}

// Calls to the asset's transfer and transferFrom are summarized and ignored: the asset is assumed to not reenter on them.
hook CALL(uint256 _, address _, uint256 _, uint256 _, uint256 _, uint256 _, uint256 _) uint256 _ {
    if (ignoredCall) {
        ignoredCall = false;
    } else {
        hasCall = true;
        if (storageChanged) {
            hasCallAfterStore = true;
        }
    }
}

hook Sstore currentContract.caps[KEY bytes32 _].allocation uint256 _ {
    if (hasCall) {
        allocationStoresAfterCall = allocationStoresAfterCall + 1;
    }
}

// Check that calls are either before the first store or after the last store (excluding the effects of accrueInterest and calls to the asset).
// Deposits are checked without liquidity adapter: with one, they are followed by an allocation, see depositOnlyWritesAllocationsAfterCall.
rule reentrancySafe(method f, env e, calldataarg data) {
    require(!storageChanged && !hasCallAfterStore && !unsafeCall && !ignoredCall, "set up the initial ghost state");
    if (f.selector == sig:forceDeallocate(address, bytes, uint256, address).selector) {
        address adapter;
        bytes adapterData;
        uint256 assets;
        address onBehalf;
    
        // Used to show that the penalty withdrawal does not deallocate again.
        require forceDeallocatePenalty(e, adapter) <= Utils.maxForceDeallocatePenalty(), "see forceDeallocatePenaltyBound in Invariants.spec";
        forceDeallocate(e, adapter, adapterData, assets, onBehalf);
    } else if (f.selector == sig:deposit(uint256, address).selector || f.selector == sig:mint(uint256, address).selector) {
        require(currentContract.liquidityAdapter == 0, "deposits with a liquidity adapter are checked in depositOnlyWritesAllocationsAfterCall");
        f(e, data);
    } else {
        f(e, data);
    }
    assert !unsafeCall;
}

// Check that deposits only write the caps allocations after calling the liquidity adapter, so the adapter is called once the deposit is complete.
rule depositOnlyWritesAllocationsAfterCall(method f, env e, calldataarg data) filtered { f -> f.selector == sig:deposit(uint256, address).selector || f.selector == sig:mint(uint256, address).selector } {
    require(!hasCall && !ignoredCall && storesAfterCall == 0 && allocationStoresAfterCall == 0, "set up the initial ghost state");
    f(e, data);
    assert storesAfterCall == allocationStoresAfterCall;
}
