// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Morpho Association

using MorphoVaultV1Adapter as MorphoVaultV1Adapter;
using VaultV2 as VaultV2;
using MetaMorphoHarness as MorphoVaultV1;
using Utils as Utils;

methods {
    function VaultV2.owner() external returns (address) envfree;
    function Utils.id(MetaMorphoHarness.MarketParams) external returns (MetaMorphoHarness.Id) envfree;

    // expectedSupplyAssets summarised as an uninterpreted ghost. Avoids modeling the
    // full Morpho Blue interest accrual logic.
    function _.expectedSupplyAssets(MetaMorphoHarness.MarketParams marketParams, address user) external => summaryExpectedSupplyAssets(marketParams, user) expect(uint256);

    // idToMarketParams summarised to return market params that are constrained to hash of the
    // given ID, ensuring consistency between Ids and their corresponding market params.
    function _.idToMarketParams(MetaMorphoHarness.Id id) external => summaryIdToMarketParams(id) expect(MetaMorphoHarness.MarketParams) ALL;

    // safeTransfer summarised to track the adapter's token balances in a ghost mapping,
    // avoiding the need to model full ERC20 contracts.
    function SafeERC20Lib.safeTransfer(address token, address to, uint256 value) internal => summarySafeTransferFrom(token, executingContract, to, value);

    // balanceOf summarised to return the adapter's ghost-tracked balance when queried for the adapter,
    // and an uninterpreted ghost value otherwise.
    function _.balanceOf(address account) external => summaryBalanceOf(calledContract, account) expect(uint256) ALL;
}

// Uninterpreted function for balanceOf of any contract other than the adapter.
ghost ghostBalanceOf(address, address) returns uint256;

// Tracks the adapter's token balances across transfers.
persistent ghost mapping(address => uint256) adapterBalanceOf;

// Returns the ghost-tracked balance for the adapter, and an uninterpreted value for all other accounts.
function summaryBalanceOf(address token, address account) returns uint256 {
    if (account == MorphoVaultV1Adapter) {
        return adapterBalanceOf[token];
    }
    return ghostBalanceOf(token, account);
}

// Uninterpreted function for the expected supply assets of a market, destructured by market params fields
// so the prover can reason about each field independently.
ghost ghostExpectedSupply(address, address, address, address, uint256, address) returns uint256;

// Returns an uninterpreted value for expectedSupplyAssets, parameterized by market params fields and user.
function summaryExpectedSupplyAssets(MetaMorphoHarness.MarketParams marketParams, address user) returns uint256 {
    return ghostExpectedSupply(marketParams.loanToken, marketParams.collateralToken, marketParams.oracle, marketParams.irm, marketParams.lltv, user);
}

// Models safeTransfer by updating the adapter's ghost token balances on sends/receives.
function summarySafeTransferFrom(address token, address from, address to, uint256 amount) {
    if (from == MorphoVaultV1Adapter) {
        // Safe require: mirrors the ERC20 revert on insufficient balance.
        adapterBalanceOf[token] = require_uint256(adapterBalanceOf[token] - amount);
    }
    if (to == MorphoVaultV1Adapter) {
        // Safe require: mirrors the ERC20 revert on balance overflow.
        adapterBalanceOf[token] = require_uint256(adapterBalanceOf[token] + amount);
    }
}

// Returns market params constrained to be consistent with the given Id.
// Assumes the market is created and present in Morpho's idToMarketParams mapping.
function summaryIdToMarketParams(MetaMorphoHarness.Id id) returns MetaMorphoHarness.MarketParams {
    MetaMorphoHarness.MarketParams marketParams;

    // Require that hashing the returned market params yields the given Id,
    // ensuring the params are consistent with the Id.
    require(Utils.id(marketParams) == id, "see hashOfMarketParamsOf in Morpho-Blue ConsistentState.spec");

    return marketParams;
}

// Verifies that calling skim does not change the adapter's accounting (realAssets) and
// skim only transfers tokens already held by the adapter to skimRecipient.
rule skimDoesNotAffectAccountingVaultV1Adapter(env e, address token) {
    uint256 realAssetsBefore = MorphoVaultV1Adapter.realAssets(e);

    MorphoVaultV1Adapter.skim(e, token);

    uint256 realAssetsAfter = MorphoVaultV1Adapter.realAssets(e);
    assert realAssetsAfter == realAssetsBefore;
}

// Verifies that setSkimRecipient reverts if and only if the sender is not the vault owner
// or msg.value is non-zero.
rule setSkimRecipientRevertConditionVaultV1Adapter(env e, address newRecipient) {
    address owner = VaultV2.owner();

    MorphoVaultV1Adapter.setSkimRecipient@withrevert(e, newRecipient);

    assert (e.msg.sender != owner || e.msg.value != 0) <=> lastReverted;
}
