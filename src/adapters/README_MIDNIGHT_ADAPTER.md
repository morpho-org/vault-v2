# Midnight Adapter

[MidnightAdapter](./MidnightAdapter.sol) lets a [Vault V2](../../README.md) allocate assets into [Midnight](https://github.com/morpho-org/midnight) markets.
The adapter holds credit on behalf of its parent vault.
It buys credit, sells credit, and withdraws repaid assets back to the vault.
The adapter uses the roles of its parent vault (curator, allocators, and sentinels).
[MidnightAdapterFactory](./MidnightAdapterFactory.sol) deploys instances of `MidnightAdapter`.
All contracts are immutable.

## Overview

### Trading and Funding

The adapter trades as a taker when a vault allocator calls `take`, or as a maker through offers approved by [sub-ratifiers](#sub-ratifiers).
Buys can use the idle assets of the vault, assets deallocated from another adapter, or repaid assets from the markets of the adapter.
Allocators and sentinels can withdraw repaid assets to the vault by directly calling its `deallocate` function.

It must have the allocator role on the vault to buy, and the allocator or sentinel role to sell.
[In-kind redemptions](#in-kind-redemptions-and-enter-gates) do not require the adapter to have these roles.

The adapter must not be set as the liquidity adapter of the vault as vault deposits would revert.

### Sub-ratifiers

Vault allocators choose which sub-ratifiers can approve offers made by the adapter.

Two sub-ratifiers are available:

- [MidnightAdapterPriceRatifierV1](./ratifiers/MidnightAdapterPriceRatifierV1.sol): Approves offers at fixed prices.
- [MidnightAdapterRateRatifierV1](./ratifiers/MidnightAdapterRateRatifierV1.sol): Approves buy offers with a minimum rate and sell offers with a maximum rate.

In both contracts, vault allocators can approve offers and cancel approvals.
Vault sentinels can only cancel approvals.

### Valuation

The adapter reports the value of its positions through `realAssets` and tracks at most 250 active markets.
For each market, `realAssets` discounts the net credit at a constant simple interest rate (`netRate`) over the remaining time to maturity (`ttm`).
The result is the _amortized value_ of the market:

```
assets = floor(netCredit / (1 + netRate * ttm))
```

On buys, the adapter adjusts `netRate` to increase amortized value by the paid assets, ignoring rounding.
Sales can realize gains or create a _shortfall_ relative to the amortized value of the sold net credit.
Unless the sold market is [force-sellable](#allocator-operational-constraints-and-force-sellable-markets), the adapter absorbs the shortfall by reducing remaining unearned interest proportionally across its markets, including force-sellable markets.
This lowers `netRate` rather than realizing an immediate loss.
The shortfall cannot exceed the combined remaining interest or the curator-set `shortfallAllowance`.
Each sale deducts its shortfall from the allowance.
Rounding can reduce more interest than the shortfall charged to this allowance.

Bad debt reduces `realAssets` immediately without changing the `netRate` of the affected market.
More active markets increase gas costs for valuation and shortfall sales.

### Caps and Duration Caps

The vault caps the stored net credit of the adapter, not its discounted value.
The caps apply to these IDs:

- Adapter
- Family: the collateral configurations, RCF threshold, and liquidator gate
- Each collateral token

Buys require non-zero absolute caps and must respect the absolute and relative limits of each ID.
The curator uses family caps to approve combinations, not individual parameters.
Markets that differ only by maturity or enter gate share the same family ID.

Up to 8 durations, fixed at deployment, let the curator limit maturity risk.
A cap for duration `d` limits total net credit in markets that mature in `d` or more.
For example, a 30-day duration cap limits total net credit in markets that mature in 30 days or later.
The vault stores the absolute and relative limits.
The adapter calculates the allocations and checks the limits on buys.
The adapter also applies a global `maxTtm` limit on buys.

### In-kind Redemptions and Enter Gates

A shareholder can buy credit from the adapter through `forceDeallocate` on the vault, even when the market has no withdrawable liquidity.
The caller pays face value plus the Midnight settlement fee, and the adapter sends the face value in assets to the vault.
The shareholder can then withdraw from the vault to complete the in-kind redemption.
The vault also charges its `forceDeallocate` penalty.
Unlike `deallocate`, this operation sells credit rather than withdrawing repaid assets from Midnight.

The adapter can be configured with an `enterGateFactory`, such as [VaultV2CompatibleEnterGateFactory](../periphery/gates/VaultV2CompatibleEnterGateFactory.sol).
When `enterGateFactory` is configured, the adapter checks two conditions before entering a gated market:

- The configured factory deployed the enter gate.
- The enter gate authorizes the factory that deployed the adapter.

`VaultV2CompatibleEnterGate` uses an arbitrary separate contract, called the _sub-gate_, to check who can normally receive credit.
The adapter can then temporarily admit shareholders during in-kind redemptions.
Shareholders can receive credit even if the sub-gate would otherwise reject them.
Without `enterGateFactory`, the enter gate must already allow the shareholder to receive credit.

### Allocator Operational Constraints and Force-sellable Markets

The curator can constrain allocator trades without a timelock:

- **Min net buy rate** (`minNetBuyRate`): Minimum simple net interest rate on buys, relative to paid assets.
- **Max net sell rate** (`maxNetSellRate`): Maximum simple net interest rate on sales. The rate is relative to the assets that the adapter receives.
- **Shortfall allowance** (`shortfallAllowance`): Remaining asset-denominated shortfall budget across markets. It starts at zero and does not refill automatically.

The curator can mark a market as `forceSellable` through a timelock.
This disables buys and permits sales that realize losses immediately, without reducing rates.
These sales use the curator-set `minForceSellPrice` instead of `maxNetSellRate` and `shortfallAllowance`.
This is useful for selling below face value after maturity.

### Timelocks

The adapter has its own [timelock system](../../README.md#timelocks), with the same flow as the vault.
Increasing `maxTtm`, enabling `forceSellable`, and setting `skimRecipient` are timelocked.
Before adding the adapter, the curator must configure its timelocks and check that no unsafe actions are pending.
Increasing a timelock does not delay actions that are already pending.

### Roles

The adapter reads roles directly from its `parentVault`:

- **Curator**: Configures the maturity limit, operational constraints, force-sellable markets, skim recipient, and timelocks. Can revoke pending changes.
- **Allocators**: Trade, withdraw repaid assets, manage sub-ratifiers, and set offer approvals and consumed amounts.
- **Sentinels**: Withdraw repaid assets, revoke pending changes, decrease `maxTtm`, and unset `forceSellable`. Can disable sub-ratifiers, cancel offer approvals, and increase consumed amounts.
