# Midnight adapter

[MidnightAdapter](./MidnightAdapter.sol) lets a [Vault V2](../../README.md) allocate assets into [Midnight](https://github.com/morpho-org/midnight) fixed-rate, fixed-maturity markets.
The adapter holds credit on behalf of its parent vault.
It buys credit, sells credit, and withdraws repaid assets back to the vault.
The adapter uses the roles of its parent vault (curator, allocators, and sentinels).
[MidnightAdapterFactory](./MidnightAdapterFactory.sol) deploys instances of `MidnightAdapter`.
All contracts are immutable.

## Non-custodial guarantees

A vault shareholder can [redeem in-kind](#in-kind-redemptions) even when a market has no withdrawable liquidity and no other buyers for the credit.
With a compatible [`enterGateFactory`](#enter-gates) configured, market enter gates cannot block these redemptions.

### In-kind redemptions

The shareholder must authorize the adapter on Midnight.
The caller must be the shareholder or an address authorized by the shareholder on Midnight.

The caller uses `forceDeallocate` on the vault to obtain credit for the shareholder.
The payment is the credit amount before pending fees plus the Midnight settlement fee.
In-kind redemptions therefore happen at a price of one asset per unit of credit, before fees, whatever the time to maturity.
The vault also charges its `forceDeallocate` penalty.
The shareholder can then withdraw from the vault to complete the in-kind redemption.

#### Enter gates

The adapter can be configured with an `enterGateFactory`, such as [VaultV2CompatibleEnterGateFactory](../periphery/gates/VaultV2CompatibleEnterGateFactory.sol).
When `enterGateFactory` is set, entering a new active market requires either no enter gate or an enter gate deployed by `enterGateFactory`.
If present, the enter gate must also authorize the factory that deployed the adapter.
`VaultV2CompatibleEnterGate` uses an arbitrary separate contract, called the sub-gate, to check who can normally receive credit.
Its `admitEnabled` setting is fixed at deployment.
If `admitEnabled` is set to true and the adapter factory is in the gate's `canAdmit` mapping, the adapter can then temporarily allow the shareholder to receive credit during `forceDeallocate`, even if the sub-gate would reject them.
With `admitEnabled = false`, adapters with `enterGateFactory` set cannot enter markets that use this gate.
Without `enterGateFactory`, the enter gate must already allow the shareholder to receive credit.
An incompatible `enterGateFactory` can allow markets whose enter gates block in-kind redemptions, without a timelock on entering those markets.

### Timelocked settings

The adapter has its own [timelock system](../../README.md#timelocks), with the same flow as the vault.
Increasing `maxTtm`, enabling `forceSellable`, force-removing a market, setting `skimRecipient`, changing a timelock duration and abdicating a timelocked function are timelocked.
Increasing [caps](#caps) or [duration caps](#duration-caps) goes through the vault timelocks.
Before adding the adapter, the curator must configure its timelocks to preserve the [non-custodial guarantees](../../README.md#non-custodial-guarantees) and check that no unsafe actions are pending.
These delays let depositors exit before the curator increases `maxTtm`, enables `forceSellable`, or force-removes a market.

## Overview

### Operational constraints

These constraints are intended for operational quality of life, not to provide guarantees to depositors.
The curator can constrain allocator trades without a timelock:

- **`minNetBuyRate`**: Minimum simple net interest rate on each buy. It starts at zero, which allows buys with no interest.
- **`maxNetSellRate`**: Maximum simple net interest rate on sales, except in [force-sellable markets](#force-sellable-markets). It starts at zero, which prevents sales below the sold net credit.
- **`shortfallAllowance`**: Total shortfall allowed from sales, in asset units. It starts at zero. Only the curator can increase it, and it is consumed at every sale below amortized value, unless the market is [force-sellable](#force-sellable-markets).
- **`minForceSellPrice`**: Minimum assets received per unit of sold net credit, set per market and used only for [force-sellable markets](#force-sellable-markets). It starts at zero, with no minimum price. It uses a price instead of a rate so sales can occur below net credit at or after maturity.

Only `minForceSellPrice` is set per market.
The other three settings are set for the whole adapter.

### Trading

The adapter trades as a taker when a vault allocator calls `take`, or as a maker through offers approved by [sub-ratifiers](#sub-ratifiers).

The adapter must have the allocator role on the vault to buy, and the allocator or sentinel role to sell, self-fund buys, or force-remove a market with stored net credit.
[`forceDeallocate`](#in-kind-redemptions) does not require the adapter to have these roles.

The adapter must not be set as the liquidity adapter of the vault as vault deposits would revert.

### Funding

Buys can use the idle assets of the vault, assets deallocated from another adapter, or repaid assets from the markets of the adapter.
On buys, the callback data of the trade selects the funding source, and allocators control it:

- When the adapter is the taker, the allocator who calls `take` sets the callback data.
- When the adapter is the maker, the callback data is part of the offer. A sub-ratifier can constrain the callback data if necessary. During [`forceDeallocate`](#in-kind-redemptions), the adapter is the maker of an offer without callback, and the shareholder sets no callback data.

Allocators and sentinels can withdraw assets from the adapter's Midnight markets by calling `deallocate` on the vault.
Withdrawals require Midnight withdrawable liquidity from repayments or liquidations, even after maturity.
Calling `deallocate` with zero assets synchronizes stored net credit after a loss without withdrawing assets.
Trades, withdrawals, and in-kind redemptions require the market loan token to match the vault asset.

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
On sales, if proceeds are above the sold net credit amortized at the market `netRate`, the adapter realizes any gain immediately.
Otherwise, the difference with the proceeds is a shortfall.
Unless the sold market is [force-sellable](#force-sellable-markets), the adapter absorbs the shortfall using proportional shares of unearned interest from active markets, including force-sellable markets.
The adapter lowers `netRate` until the shortfall is covered, instead of realizing an immediate loss.
For these sales, the adapter deducts the shortfall from `shortfallAllowance`.
The sale reverts if the shortfall exceeds total unearned interest or the curator-set `shortfallAllowance`.
If the sold market is force-sellable, the adapter realizes the shortfall immediately, without reducing `netRate` or consuming `shortfallAllowance`.

Bad debt reduces `realAssets` immediately without changing the `netRate` of the affected market.

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

### Force-sellable markets

The curator can mark a market as `forceSellable` through a timelock.
This disables buys and permits sales that realize losses immediately, without reducing `netRate` to absorb them.
These sales use the curator-set `minForceSellPrice` instead of `maxNetSellRate` and `shortfallAllowance`.
This permits sales for fewer assets than the sold net credit after maturity.

### Force-removed markets

The curator can permanently remove a market from the adapter through the timelocked `forceRemove` function.
This removes its amortized net credit from `realAssets` and its stored net credit from cap allocations.
The credit balance of the adapter on Midnight does not change.
Buys, sales, withdrawals, and in-kind redemptions in that market then revert.
When submitting `forceRemove`, the curator should set at least one cap for the market to zero to prevent further buys.

### Skim

The `skimRecipient` can call `skim` to collect any token held by the adapter, including rewards.

### Roles

The adapter reads roles directly from its `parentVault`:

- **Curator**: Configures `maxTtm`, operational constraints, force-sellable markets, `skimRecipient`, and timelocks. Can submit market removals and revoke pending changes.
- **Allocators**: Trade, withdraw repaid assets, manage sub-ratifiers, approve offers, and cancel offer approvals.
- **Sentinels**: Withdraw repaid assets, revoke pending changes, decrease `maxTtm`, and unset `forceSellable`. Can disable sub-ratifiers and cancel offer approvals.
