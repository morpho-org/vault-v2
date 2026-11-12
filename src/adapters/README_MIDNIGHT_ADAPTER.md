# Midnight adapter

[MidnightAdapter](./MidnightAdapter.sol) lets a [Vault V2](../../README.md) allocate assets into [Midnight](https://github.com/morpho-org/midnight) fixed-rate, fixed-maturity markets.
The adapter holds credit on behalf of its parent vault.
It buys credit, sells credit, and withdraws repaid assets back to the vault.
The adapter uses the roles of its parent vault (curator, allocators, and sentinels).
[MidnightAdapterFactory](./MidnightAdapterFactory.sol) deploys instances of `MidnightAdapter`.
All contracts are immutable.

## Overview

### Trading

The adapter trades as a taker when a vault allocator calls `take`, or as a maker through offers approved by [sub-ratifiers](#sub-ratifiers).

The adapter must have the allocator role on the vault to buy, and the allocator or sentinel role to sell, self-fund buys, or force-remove a market with stored net credit.
[`forceDeallocate`](#in-kind-redemptions) does not require the adapter to have these roles.

The adapter must not be set as the liquidity adapter of the vault as vault deposits would revert.

### Funding

Buys can use the idle assets of the vault, assets deallocated from another adapter, or repaid assets from the markets of the adapter.
Allocators and sentinels can withdraw repaid assets by calling `deallocate` on the vault.
Withdrawals require available liquidity from repayments or liquidations, even after maturity.
Calling `deallocate` with zero assets synchronizes stored net credit after a loss without withdrawing assets.
Trades, withdrawals, and in-kind redemptions require the market's loan token to be the vault's asset.

### Sub-ratifiers

Vault allocators choose which sub-ratifiers can approve offers made by the adapter.

Two sub-ratifiers are available:

- [MidnightAdapterPriceRatifierV1](./ratifiers/MidnightAdapterPriceRatifierV1.sol): Approves offers at fixed prices.
- [MidnightAdapterRateRatifierV1](./ratifiers/MidnightAdapterRateRatifierV1.sol): Approves buy offers with a minimum rate and sell offers with a maximum rate.

In both contracts, vault allocators can approve offers and cancel offer approvals.
Vault sentinels can only cancel offer approvals.

### Valuation

Net credit is the credit due at maturity after pending Midnight fees.
An active market is a market where the adapter stores non-zero net credit.
The adapter tracks at most 250 active markets.

`realAssets` returns the total amortized net credit across active markets.
For each market, the adapter amortizes net credit using `netRate`, a simple interest rate, over the time left before maturity (`ttm`):

```
assets = floor(netCredit / (1 + netRate * ttm))
```

Unearned interest is the difference between net credit and amortized net credit.

On buys, the adapter adjusts `netRate` based on the net credit bought and the assets paid.
On sales, if proceeds are above the amortized net credit sold, the adapter realizes any gain immediately.
Otherwise, the difference with the proceeds is a shortfall.
Unless the sold market is [force-sellable](#force-sellable-markets), the adapter absorbs the shortfall using proportional shares of unearned interest from active markets, including force-sellable markets.
The adapter lowers `netRate` until the shortfall is covered, instead of realizing an immediate loss.
It stops reducing rates once the realized shortfall covers the sale's shortfall.
Rounding can consume slightly more unearned interest than the shortfall deducted from the allowance.
For these sales, the adapter deducts the shortfall from `shortfallAllowance`.
The sale reverts if the shortfall exceeds total unearned interest or the curator-set `shortfallAllowance`.
If the sold market is force-sellable, the adapter realizes the shortfall immediately, without reducing `netRate` or consuming `shortfallAllowance`.

Bad debt reduces `realAssets` immediately without changing the `netRate` of the affected market, with the loss discounted over the remaining term.

Position amortized values and rates are rounded down on buys, sales, and `realAssets` evaluations, which can accrue some interest earlier.
Stored net rates fit in `uint64`; extremely high rates can make buys revert.

### Caps

The vault caps the stored net credit of the adapter, not its amortized net credit.
The caps apply to these IDs:

- Adapter
- Family: the collateral configurations, RCF threshold, and liquidator gate
- Each collateral token

Buys require non-zero absolute caps and must respect the absolute and relative caps of each ID.
The curator uses family caps to approve combinations, not individual parameters.
Markets that differ only by maturity or enter gate share the same family ID.

### Duration caps

Up to 8 durations, fixed at deployment, let the curator limit maturity risk.
A cap for duration `d` limits total net credit in markets that mature in `d` or more.
For example, a 30-day duration cap limits total net credit in markets that mature in 30 days or later.
The adapter enforces duration caps itself.
The adapter also enforces `maxTtm`, the maximum time to maturity for buys across all markets.

### In-kind redemptions

A shareholder can redeem in-kind even when a market has no withdrawable liquidity.
The shareholder must authorize the adapter on Midnight.
The caller must be the shareholder or an address authorized by the shareholder on Midnight.

The caller uses `forceDeallocate` on the vault to obtain credit for the shareholder.
The payment is the credit amount before pending fees plus the Midnight settlement fee.
The vault also charges its `forceDeallocate` penalty.
The shareholder can then withdraw from the vault to complete the in-kind redemption.

### Enter gates

The adapter can be configured with an `enterGateFactory`, such as [VaultV2CompatibleEnterGateFactory](../periphery/gates/VaultV2CompatibleEnterGateFactory.sol).
When `enterGateFactory` is set, entering a new active market requires either no enter gate or an enter gate deployed by `enterGateFactory`.
If present, the enter gate must also authorize the factory that deployed the adapter.
`VaultV2CompatibleEnterGate` uses an arbitrary separate contract, called the sub-gate, to check who can normally receive credit.
During `forceDeallocate`, the adapter temporarily allows the shareholder to receive credit even if the sub-gate would reject them, then clears the admission in its buyer callback before Midnight transfers the loan token.
Without `enterGateFactory`, the enter gate must already allow the shareholder to receive credit.
The in-kind redemption guarantee requires a compatible factory and gates, such as `VaultV2CompatibleEnterGateFactory` and its gates.
An arbitrary factory can allow markets whose gates block in-kind redemptions, without a timelock on entering those markets.

### Operational constraints

The curator can constrain allocator trades without a timelock:

- **`minNetBuyRate`**: Minimum simple net interest rate on buys, relative to paid assets.
- **`maxNetSellRate`**: Maximum simple net interest rate on sales, relative to the assets that the adapter receives.
- **`shortfallAllowance`**: Remaining budget for accepted economic shortfall from sales across markets, in asset units. It starts at zero and does not refill automatically.

`maxTtm` and `minNetBuyRate` share one storage slot as `uint128` values.
`maxNetSellRate` and `shortfallAllowance` share another storage slot as `uint128` values.
Setters reject values that do not fit in `uint128`.

### Force-sellable markets

The curator can mark a market as `forceSellable` through a timelock.
This disables buys and permits sales that realize losses immediately, without reducing `netRate` to absorb them.
These sales use the curator-set `minForceSellPrice` instead of `maxNetSellRate` and `shortfallAllowance`.
This permits sales for fewer assets than the sold net credit after maturity.

### Force-removed markets

The curator submits `forceRemove(marketId)` through the adapter's timelock system; anyone can execute it after the delay.
It irreversibly sets stored net credit to zero and removes the market from active markets, without moving its Midnight credit.
If stored net credit was non-zero, it also deallocates that net credit from the vault's caps with zero assets withdrawn.
The position is written off from `realAssets`, and buys, sales, withdrawals, and in-kind redemptions of the market then revert.
When submitting `forceRemove`, it is recommended to set at least one of the market's ID caps to zero to prevent buys just before removal.

### Events

`ForceRemove` reports the market ID and the stored net credit removed.
`WithdrawToVault` reports withdrawn assets and the new net credit, including zero-asset synchronizations.
`Sell` reports the shortfall and the remaining `shortfallAllowance`.
`ReduceRate` reports each market's reduced rate when absorbing a shortfall.

### Skim

The `skimRecipient` can call `skim` to collect any token held by the adapter, including rewards.

### Timelocks

The adapter has its own [timelock system](../../README.md#timelocks), with the same flow as the vault.
Increasing `maxTtm`, enabling `forceSellable`, force-removing a market, and setting `skimRecipient` are timelocked.
Before adding the adapter, the curator must configure its timelocks to preserve the [non-custodial guarantees](../../README.md#non-custodial-guarantees) and check that no unsafe actions are pending.
These delays let depositors exit before the curator increases `maxTtm`, enables `forceSellable`, or force-removes a market.

### Roles

The adapter reads roles directly from its `parentVault`:

- **Curator**: Configures `maxTtm`, operational constraints, force-sellable markets, `skimRecipient`, and timelocks. Can submit market removals and revoke pending changes.
- **Allocators**: Trade, withdraw repaid assets, manage sub-ratifiers, approve offers, and cancel offer approvals.
- **Sentinels**: Withdraw repaid assets, revoke pending changes, decrease `maxTtm`, and unset `forceSellable`. Can disable sub-ratifiers and cancel offer approvals.
