// SPDX-License-Identifier: MIT
// Copyright (c) 2025 Morpho Association

using VaultV2 as VaultV2;

// This specification checks that the Midnight adapter's withdrawToVault with withdrawnAssets=0 does not revert.
// The parent vault is linked, while Midnight and the asset are summarized.
methods {
    function multicall(bytes[]) external => HAVOC_ALL DELETE;

    function VaultV2.isAdapter(address) external returns (bool) envfree;
    function VaultV2.isAllocator(address) external returns (bool) envfree;
    function VaultV2.isSentinel(address) external returns (bool) envfree;

    // `liquidationLocked` is read from a ghost, to be able to require that the adapter's position is not liquidation-locked.
    function _.liquidationLocked(bytes32 marketId, address user) external => ghostLiquidationLocked[marketId][user] expect(bool) ALL;

    // Assume that Midnight's zero withdraw does not revert: it only touches the market and updates the adapter's position.
    function _.withdraw(MidnightAdapter.Market, uint256, address, address) external => NONDET ALL;

    // Assume that reading the adapter's net credit and the market's loss factor in Midnight does not revert.
    function MidnightAdapter.currentNetCredit(bytes32) internal returns (uint128) => NONDET;
    function _.lossFactor(bytes32 marketId) external => ghostLossFactor[marketId] expect(uint128) ALL;

    // The id is a nested hash of the encoded market, which the prover handles poorly, so any id is allowed.
    function IdLib.toId(MidnightAdapter.Market memory) internal returns (bytes32) => NONDET;

    // The returned ids are constrained in summaryDeallocate, where the vault reads them back from the adapter.
    function ids(MidnightAdapter.Market memory) internal returns (bytes32[] memory) => arbitraryIds();

    // Adapter's `deallocate` is assumed to not revert when called back by the vault and returns 6 distinct ids, with post-conditions on the returned ids and change as specified in summaryDeallocate.
    // Its checks hold on this path, since the vault is the parent vault and the caller is the adapter itself, and its max approval of the vault is assumed to not revert.
    function _.deallocate(bytes data, uint256 assets, bytes4 selector, address caller) external => summaryDeallocate(data, assets, selector, caller) expect(bytes32[], int256) ALL;

    // Assume that SafeERC20Lib.safeTransferFrom does not revert.
    function SafeERC20Lib.safeTransferFrom(address, address, address, uint256) internal => NONDET;
}

ghost mapping(bytes32 => mapping(address => bool)) ghostLiquidationLocked;

// Midnight's loss factor of each market, which is a uint128 as returned by Midnight's lossFactor.
ghost mapping(bytes32 => uint128) ghostLossFactor;

// Maximum signed 256-bit integer, used to bound int256 values.
definition max_int256() returns int256 = (2 ^ 255) - 1;

function arbitraryIds() returns bytes32[] {
    bytes32[] idsArray;
    return idsArray;
}

// Post-conditions on the adapter's deallocate required for the canWithdrawToVaultZero rule.
function summaryDeallocate(bytes data, uint256 assets, bytes4 selector, address caller) returns (bytes32[], int256) {
    bytes32[] ids;
    int256 change;

    // for simplicity, we assume a market with one collateral, for which the adapter returns exactly 4 + 2 * 1 ids.
    require ids.length == 6, "for simplicity, assume a fixed number of ids";
    require forall uint256 i. forall uint256 j. i < ids.length && j < ids.length && i != j => ids[i] != ids[j], "specification requires adapters to return unique ids";

    require forall uint256 i. i < ids.length => VaultV2.caps[ids[i]].allocation <= max_int256(), "see allocationIsInt256";

    // Post-conditions on the returned ids and change that ensure withdrawToVault with zero does not revert:
    require forall uint256 i. i < ids.length => VaultV2.caps[ids[i]].allocation > 0, "assume that all ids have a positive allocation, else deallocate reverts (see deallocateInputValidation)";
    require forall uint256 i. i < ids.length => VaultV2.caps[ids[i]].allocation + change >= 0, "assume that the allocation of each id is at least the decrease of the market's net credit";
    require forall uint256 i. i < ids.length => VaultV2.caps[ids[i]].allocation + change <= max_int256(), "assume that the change doesn't overflow int256 on any id";

    return (ids, change);
}

// withdrawToVault with withdrawnAssets=0 triggers the adapter to update the allocation tracking in caps with its live net credit in Midnight, without selling.
// The call goes through MidnightAdapterHarness, which builds a market with one collateral in memory.
// This rule verifies the liveness property that `withdrawToVault()` can be called by anyone with withdrawnAssets=0 with the following pre-conditions:
//   1. The adapter's position in the market is not liquidation-locked in Midnight.
//   2. The adapter is registered in the vault and is an allocator or a sentinel of the vault.
//   3. A market with a non-zero stored net credit is in the market list at its stored index.
//   4. Midnight's zero withdraw, and reading the adapter's net credit and the market's loss factor, do not revert.
//   5. Assumptions on the adapter's deallocate as specified in summaryDeallocate.
//   6. SafeERC20Lib.safeTransferFrom and the adapter's max approval of the vault do not revert.
rule canWithdrawToVaultZero(env e, uint256 chainId, address marketMidnight, address loanToken, address collateralToken, uint256 lltv, uint256 liquidationCursor, address oracle, uint256 maturity, uint256 rcfThreshold, address enterGate, address liquidatorGate) {
    // call set-up
    require e.msg.value == 0, "setup call to have no ETH value";
    require VaultV2.isAdapter(currentContract), "the adapter must be registered in the vault";
    require VaultV2.isAllocator(currentContract) || VaultV2.isSentinel(currentContract), "the adapter must be an allocator or a sentinel of the vault";

    // the market id is not computed, so the lock is required to be unset on any market id.
    require forall bytes32 marketId. !ghostLiquidationLocked[marketId][currentContract], "assume that the adapter's position is not liquidation-locked";

    require forall bytes32 marketId. currentContract.marketData[marketId].netCredit != 0 => currentContract.marketData[marketId].index < currentContract.marketIds.length, "see nonZeroNetCreditIsListed in NetCreditMidnightAdapter.spec";

    // call withdrawToVault with zero withdrawn assets.
    withdrawToVaultOneCollateral@withrevert(e, chainId, marketMidnight, loanToken, collateralToken, lltv, liquidationCursor, oracle, maturity, rcfThreshold, enterGate, liquidatorGate, 0);

    assert !lastReverted;
}
