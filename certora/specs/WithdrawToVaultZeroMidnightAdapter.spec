// SPDX-License-Identifier: MIT
// Copyright (c) 2025 Morpho Association

using VaultV2 as VaultV2;

// Model of the adapter's environment: the parent vault is linked, Midnight and the asset are not in the scene.
methods {
    function multicall(bytes[]) external => HAVOC_ALL DELETE;

    function VaultV2.isAdapter(address) external returns (bool) envfree;
    function VaultV2.isAllocator(address) external returns (bool) envfree;
    function VaultV2.isSentinel(address) external returns (bool) envfree;

    // Whether the adapter's position in a Midnight market is liquidation-locked, read from a ghost so that the rule can require it to be unlocked.
    function _.liquidationLocked(bytes32 marketId, address user) external => ghostLiquidationLocked[marketId][user] expect(bool) ALL;

    // Midnight's zero withdraw for the adapter is assumed to not revert: it only touches the market and updates the adapter's position.
    function _.withdraw(MidnightAdapter.Market, uint256, address, address) external => NONDET ALL;

    // Reading the adapter's position and the market's loss factor in Midnight is assumed to not revert, and can return any value.
    function currentNetCredit(bytes32) internal returns (uint128) => NONDET;
    function _.lossFactor(bytes32) external => NONDET ALL;

    // The id is a nested hash of the ABI-encoded market, which the prover handles poorly; any id is allowed.
    function IdLib.toId(MidnightAdapter.Market memory) internal returns (bytes32) => NONDET;

    // The ids are constrained by summaryDeallocate instead, through the values the vault reads back from the adapter.
    function ids(MidnightAdapter.Market memory) internal returns (bytes32[] memory) => arbitraryIds();

    // The vault's call back into the adapter, which returns the ids and the change encoded by withdrawToVault.
    function _.deallocate(bytes data, uint256 assets, bytes4 selector, address caller) external => summaryDeallocate(data, assets, selector, caller) expect(bytes32[], int256) ALL;

    // The asset is assumed to not revert on zero-amount transfers.
    function SafeERC20Lib.safeTransferFrom(address, address, address, uint256) internal => NONDET;
}

ghost mapping(bytes32 => mapping(address => bool)) ghostLiquidationLocked;

// Maximum signed 256-bit integer, used to bound int256 values.
definition max_int256() returns int256 = (2 ^ 255) - 1;

function arbitraryIds() returns bytes32[] {
    bytes32[] idsArray;
    return idsArray;
}

// Post-conditions on the ids and change returned to the vault, required for the canWithdrawToVaultZero rule.
function summaryDeallocate(bytes data, uint256 assets, bytes4 selector, address caller) returns (bytes32[], int256) {
    bytes32[] ids;
    int256 change;

    require ids.length == 6, "simplified market with one collateral, for which the adapter returns 4 + 2 * 1 ids";
    require forall uint256 i. forall uint256 j. i < ids.length && j < ids.length && i != j => ids[i] != ids[j], "ids must be unique";

    require forall uint256 i. i < ids.length => VaultV2.caps[ids[i]].allocation <= max_int256(), "see allocationIsInt256 in Invariants.spec";
    require forall uint256 i. i < ids.length => VaultV2.caps[ids[i]].allocation > 0, "assumption on the allocations of the market's ids, else deallocate reverts (see deallocateInputValidation in AllocateDeallocateInputValidation.spec)";
    require forall uint256 i. i < ids.length => VaultV2.caps[ids[i]].allocation + change >= 0, "assumption that the allocation of each id is at least the stored net credit of the market";
    require forall uint256 i. i < ids.length => VaultV2.caps[ids[i]].allocation + change <= max_int256(), "assumption on the adapter's change";

    return (ids, change);
}

// withdrawToVault with withdrawnAssets=0 makes the adapter sync the vault's allocations of a market with its live net credit in Midnight, without selling.
// This rule verifies the liveness property that withdrawToVault can be called by anyone with withdrawnAssets=0 with the following pre-conditions:
//   1. The adapter's position in the market is not liquidation-locked in Midnight.
//   2. The adapter is registered in the vault and has the allocator or sentinel role in it.
//   3. A market with a non-zero stored net credit is in the market list at its stored index.
//   4. Midnight's zero withdraw, and reading the adapter's position and the market's loss factor, do not revert.
//   5. A market with one collateral, whose 6 unique ids and change satisfy summaryDeallocate.
//   6. The asset does not revert on zero-amount transfers.
rule canWithdrawToVaultZero(env e, MidnightAdapter.Market market) {
    require e.msg.value == 0, "withdrawToVault is non-payable";

    // Midnight's lock is checked on any market id, since ids are not computed.
    require forall bytes32 marketId. !ghostLiquidationLocked[marketId][currentContract], "the adapter's position is not liquidation-locked";

    require VaultV2.isAdapter(currentContract), "the adapter must be registered in the vault";
    require VaultV2.isAllocator(currentContract) || VaultV2.isSentinel(currentContract), "the adapter must have the allocator or sentinel role in the vault";

    require forall bytes32 marketId. currentContract.marketData[marketId].netCredit != 0 => currentContract.marketData[marketId].index < currentContract.marketIds.length, "see nonZeroNetCreditIsListed in NetCreditMidnightAdapter.spec";

    withdrawToVault@withrevert(e, market, 0);

    assert !lastReverted;
}
