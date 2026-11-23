# Midnight adapter

[MidnightAdapter](./MidnightAdapter.sol) lets a [Vault V2](../../../README.md) allocate assets into [Midnight](https://github.com/morpho-org/midnight) fixed-rate, fixed-maturity markets.
It buys, sells and holds credit on behalf of the vault, and withdraws repaid assets back to the vault.
The adapter uses the roles of its parent vault (curator, allocators, and sentinels).
[MidnightAdapterFactory](./MidnightAdapterFactory.sol) deploys instances of `MidnightAdapter`.
All contracts are immutable.

## Non-custodiality and depositor guarantees

A vault depositor can [redeem in-kind](#in-kind-redemptions) even when a market has no withdrawable liquidity and no other buyers for the credit.
With a compatible [`enterGateFactory`](#enter-gates) configured, market enter gates cannot block these redemptions.

### In-kind redemptions

The vault shareholder uses `forceDeallocate` on the vault to obtain credit from the adapter.
The payment is the credit amount before pending fees plus the Midnight settlement fee.
In-kind redemptions therefore happen at a price of one asset per unit of credit, plus fees, whatever the time to maturity.
The vault also charges its `forceDeallocate` penalty.
The shareholder can then withdraw from the vault to complete the in-kind redemption.

### Enter gates

The adapter can be configured with an `enterGateFactory`, such as [IKRCompatibleEnterGateFactory](./gates/IKRCompatibleEnterGateFactory.sol).
When `enterGateFactory` is set, the adapter can only enter markets that allow in-kind redemptions (i.e. without gate or with an enter gate deployed by `enterGateFactory` that ensures IKR can be done).
If `admitEnabled` (fixed at deployment) is set to true and the adapter factory is in the gate's `admitterFactory` mapping, the adapter can then temporarily allow the shareholder to receive credit during `forceDeallocate`, even if the sub-gate would reject them, effectively ensuring that IKR can be done.
With `admitEnabled = false`, adapters with `enterGateFactory` set cannot enter markets that use this gate.
`IKRCompatibleEnterGate` uses an arbitrary separate contract, called the sub-gate, to check who can normally receive credit.
Registered adapter factories are trusted to always return true to `isCreated` on adapters they deployed, and their adapters must behave correctly. Otherwise, in-kind redemptions can be blocked even when the gate's `admitEnabled` is set to true.

### Timelocked settings

The adapter has its own [timelock system](../../../README.md#timelocks), with the same flow as the vault.
Decreasing `minNetBuyRate`, increasing `maxNetSellRate`, `shortfallAllowance` or `maxTtm`, enabling `forceSellable`, force-removing a market, setting `skimRecipient`, changing a timelock duration and abdicating a timelocked function are timelocked.
Increasing [caps](#caps) or [duration caps](#duration-caps) goes through the vault's timelocks.
These delays ensure that depositors can always withdraw their assets before any critical configuration change takes effect.

### Caps

The vault caps the stored net credit of the adapter, not its amortized net credit.
The granularity of the caps is the following:

- Adapter-wide
- Market "family": collateral parameters, RCF threshold, liquidator gate, and enter gate, regardless of maturity
- Each collateral token

### Duration caps

Up to 8 durations, fixed at deployment, let the curator limit duration risk.
A cap for duration `d` limits total net credit in markets that mature in `d` or more.
The adapter also enforces `maxTtm`, the maximum time to maturity for buys across all markets.

## Other features

### Trading

The adapter trades as a taker when a vault allocator calls `take`, or as a maker through offers approved by [sub-ratifiers](#sub-ratifiers).

The adapter must have the allocator role on the vault to buy credit.
It must have the allocator or sentinel role to sell or force-remove a market with stored net credit.
[`forceDeallocate`](#in-kind-redemptions) does not require the adapter to have these roles.

The adapter cannot be used as liquidity adapter.

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
On sales, the amortized value sold is the difference between the market's amortized values before and after the sale, at the same rate.
If proceeds are above that value, the adapter realizes any gain immediately.
Otherwise, the difference with the proceeds is a shortfall.

Unless the sold market is [force-sellable](#force-sellable-markets), the adapter absorbs the shortfall using proportional shares of unearned interest from active markets.
The adapter lowers `netRate` until the shortfall is covered, instead of realizing an immediate loss.
The sale reverts if the shortfall exceeds total unearned interest or the curator-set `shortfallAllowance`.
If the sold market is force-sellable, the adapter realizes the shortfall immediately, without reducing `netRate` or consuming `shortfallAllowance`.

Bad debt reduces `realAssets` immediately without changing the `netRate` of the affected market.

### Funding

Buys can use the idle assets of the vault, assets deallocated from another adapter, or withdrawable liquidity from the markets of the adapter.
On buys, the callback data of the trade selects the funding source, and allocators control it (as part of the take function arguments, or of the offer callback data).
Allocators and sentinels can withdraw assets from a Midnight market of the adapter.

### Sub-ratifiers

Vault allocators choose which sub-ratifiers can approve offers made by the adapter.

Two sub-ratifiers are available:

- [MidnightAdapterPriceRatifierV1](./ratifiers/MidnightAdapterPriceRatifierV1.sol): For offers at fixed prices.
- [MidnightAdapterRateRatifierV1](./ratifiers/MidnightAdapterRateRatifierV1.sol): For buy offers with a minimum rate and sell offers with a maximum rate.

In both contracts, vault allocators can approve offers and cancel offers.
Vault sentinels can only cancel offers.

### Operational constraints

These constraints are intended for operational quality of life, not to provide guarantees to depositors.
The curator can constrain allocator trades through these settings:

- **`minNetBuyRate`**: Minimum simple net interest rate on each buy.
- **`maxNetSellRate`**: Maximum simple net interest rate on sales, except in [force-sellable markets](#force-sellable-markets).
- **`shortfallAllowance`**: Total shortfall allowed from sales, in asset units. It is consumed at every sale below amortized value, unless the market is [force-sellable](#force-sellable-markets).
- **`minForceSellPrice`**: Minimum assets received per unit of sold net credit, set per market and used only for [force-sellable markets](#force-sellable-markets).

Only `minForceSellPrice` is set per market.
The other three settings are set for the whole adapter.

`decreaseMinNetBuyRate`, `increaseMaxNetSellRate` and `increaseShortfallAllowance` are timelocked. Their opposite-direction functions are curator-only and immediate. `setMinForceSellPrice` is curator-only and immediate in either direction.
These timelocks are not hard guarantees on depositors' future interest, and the adapter does not need them to be noncustodial.

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

### Skim

The `skimRecipient` can call `skim` to collect any token held by the adapter, including rewards.

### Roles

The adapter reads roles directly from its `parentVault`:

- **Curator**: Configures `maxTtm`, operational constraints (with timelocks when relaxing them), force-sellable markets, `skimRecipient`, and timelocks. Can submit market removals and revoke pending changes.
- **Allocators**: Trade, withdraw repaid assets, manage sub-ratifiers, approve offers, and cancel offer approvals.
- **Sentinels**: Withdraw repaid assets, revoke pending changes, decrease `maxTtm`, and unset `forceSellable`. Can disable sub-ratifiers and cancel offer approvals.

## Midnight Enter Gates and Subgates

These contracts control increases in credit or debt in Midnight markets, not transfers of vault shares or assets.
Midnight calls the gate at `Market.enterGate`. That gate can call a subgate to check permissions.

### `IKRCompatibleEnterGate`

This is a Midnight enter gate, not a Vault V2 gate.
One gate can be the enterGate of multiple markets.
For ordinary permission checks, the gate calls its `subGate` with the account.
During `forceDeallocate`, a Midnight adapter from a registered factory can temporarily admit a shareholder of its parent vault to receive credit without subgate approval.
The adapter sells through its own offer and is the buyer callback of that sale: it clears the admission in that callback, before Midnight transfers the loan token, so neither the buyer nor the token can reuse it.
`IKRCompatibleEnterGateFactory` deploys `IKRCompatibleEnterGate` contracts.

### `WhitelistEnterSubGate`

A subgate that restricts which accounts can increase their credit or debt in the markets of the gates that use it.
`IKRCompatibleEnterGate` calls this subgate with an account.
It cannot be used directly as a Midnight or Vault V2 gate.

Each side (credit, debt) has one whitelist for all markets: only whitelisted accounts can enter on that side.
Each side has its own role setter, who grants or revokes the whitelister role on that side.
Whitelisters edit the lists directly with `setIsWhitelisted` or allow to edit the list by EIP-712 signatures used by `setIsWhitelistedWithSig`.
`setIsWhitelistedWithSig` accepts a stale nonce when the account is already set to the signed value. The signature must still be unexpired and from a current whitelister.
A side can be made open at deployment, letting any account enter on that side (forever).
`WhitelistEnterSubGateFactory` deploys `WhitelistEnterSubGate` contracts.
