# Midnight Adapter

[MidnightAdapter](./MidnightAdapter.sol) lets a [Vault V2](../../README.md) allocate assets into [Midnight](https://github.com/morpho-org/midnight) fixed-rate, fixed-maturity markets.
The adapter holds credit on behalf of its parent vault.
It buys credit, sells credit, and withdraws repaid assets back to the vault.
The adapter uses the roles of its parent vault (curator, allocators, and sentinels).
[MidnightAdapterFactory](./MidnightAdapterFactory.sol) deploys instances of `MidnightAdapter`.
All contracts are immutable.

## Overview

### Trading and Funding

Trades on Midnight trigger allocations and deallocations on the adapter through the `onBuy` and `onSell` callbacks.
These callbacks then call `allocate` and `deallocate` on the parent vault.
Because of this flow:

- The adapter must have the **allocator** role on the parent vault to trade.
- Do not set the Midnight adapter as the liquidity adapter of the parent vault. `allocate` accepts only calls from the adapter itself, so vault deposits revert.

The adapter trades in three ways:

- **As a taker**: A vault allocator calls `take` on the adapter to fill an offer on Midnight.
- **As a maker**: Any user on Midnight fills an offer that the adapter made and that an enabled [sub-ratifier](#sub-ratifiers) approved.
- **In-kind redemption**: During `forceDeallocate`, the adapter sells credit to a vault shareholder. See [In-kind Redemptions and Enter Gates](#in-kind-redemptions-and-enter-gates).

While Midnight executes a sale by the adapter in a market, no offer of the adapter in that market can be filled.

When the adapter buys credit, the callback data of the trade selects the funding source.
For a taker trade, the callback data is `takerCallbackData`.
For a maker trade, the callback data is `offer.callbackData`.
The funding sources are:

- `abi.encode(address(0), "")`: Uses idle assets from the parent vault.
- `abi.encode(fundingAdapter, fundingData)`: Deallocates assets from `fundingAdapter` on the parent vault, then allocates them to the Midnight adapter.
- `abi.encode(address(this), abi.encode(fundingMarket))`: Withdraws repaid assets from `fundingMarket` on the adapter. To do this, the adapter calls `deallocate` on the parent vault with `data` that requests a withdrawal from `fundingMarket`.

The adapter has the allocator role, so a trade can deallocate assets from any adapter of the parent vault.
Allocators control the callback data:

- For a taker trade, the allocator who calls `take` sets the callback data.
- For a maker trade, the callback data is part of the offer. A sub-ratifier approves the offer only if the offer is in a Merkle tree that the allocators approved.

Borrowers repay a market directly or through liquidations, possibly before maturity.
Allocators and sentinels can withdraw the repaid assets to the idle assets of the vault.
To do this, they call `deallocate` on the parent vault with `data` that requests a withdrawal from `market`.
Anyone can also do this with `forceDeallocate` and the same `data`.
In that case, the vault charges its `forceDeallocate` penalty.

### Sub-ratifiers

For maker offers, the adapter is its own Midnight ratifier (`IRatifier`).
The adapter forwards ratification checks to sub-ratifiers that the vault allocators enable (`setIsSubRatifier`).
Allocators and sentinels can also call `setConsumed` on the adapter to update the consumed amount of an offer group on Midnight.

Two sub-ratifiers are available:

- [MidnightAdapterPriceRatifierV1](./ratifiers/MidnightAdapterPriceRatifierV1.sol): Approves Merkle trees of offers at fixed ticks.
- [MidnightAdapterRateRatifierV1](./ratifiers/MidnightAdapterRateRatifierV1.sol): Approves Merkle trees of offers with a minimum buy rate or a maximum sell rate. The rate limit depends on the remaining time to maturity.

In both contracts, vault allocators can approve Merkle roots and cancel approvals.
Vault sentinels can only cancel approvals.
Allocators and sentinels (or addresses that they authorize on Midnight) can do this directly with `setIsRootRatified`, or with an EIP-712 signature through `setIsRootRatifiedWithSig`.

### Valuation

The adapter holds positions in at most `MAX_MARKETS` (250) active markets with non-zero net credit (`netCredit = credit - pendingFee`, the face value at maturity).
For each market, `realAssets` discounts the net credit at a constant simple interest rate (`netRate`) over the remaining time to maturity (`ttm`).
The result is the _amortized value_ of the market:

```
assets = floor(netCredit / (1 + netRate * ttm))
```

When the adapter buys credit, it updates `netRate`.
The new amortized value of the market is then its previous amortized value plus the paid assets.
The adapter rounds `netRate` down and realizes any rounding remainder immediately.

When the adapter sells credit, the _shortfall_ is the amortized value of the sold net credit minus the sale assets, or zero if the sale assets are higher.

- If the shortfall is zero, `netRate` does not change. The adapter realizes any gain immediately.
- If the shortfall is more than zero, the adapter does not realize it immediately:
  - The amortized value of the market decreases only by the sale assets.
  - The adapter decreases `netRate` on the remaining net credit, so the market earns less interest until maturity.
  - The shortfall must not be more than the remaining unearned interest of the market. Otherwise, the sale reverts (`ShortfallTooHigh`).

If a market takes bad debt on Midnight (`lossFactor` changes), `realAssets` immediately uses the reduced net credit.
This change realizes the principal loss and decreases the remaining unearned interest in proportion to the loss.

The gas cost of `realAssets` increases with the number of active markets, because `realAssets` reads `lossFactor` from Midnight for each market.
The parent vault calls `realAssets` at each interest accrual, so many active markets make most vault operations more expensive.

### Caps and Duration Caps

On each allocation and deallocation, the adapter reports the change in stored `netCredit` to the cap system of the parent vault for these market IDs (`ids(market)`):

- Adapter
- Liquidator gate (if non-zero)
- RCF threshold
- Each collateral token
- Each collateral configuration

The adapter can buy credit in a market only if each of these IDs has a non-zero absolute cap on the parent vault.
With these caps, the curator selects the gates, RCF thresholds, and collaterals that the adapter accepts.

To limit maturity risk, the adapter has up to 8 strictly increasing durations (`durations`).
These durations are set at deployment.
The adapter also applies a global `maxTtm` limit on buys.
Each duration `d` caps the credit in markets that mature `d` or more from now.
The total stored `netCredit` of these markets must stay within the absolute and relative caps of the duration ID of `d` on the parent vault.
For example, with durations of 30 and 90 days, only the 30-day caps limit the credit in a market that matures in 60 days. When the market is less than 30 days from maturity, no duration cap limits its credit.
The adapter checks these caps on every buy.
The parent vault stores the caps, and the adapter calculates the allocations.

For a buy, every configured duration up to the remaining time to maturity of the market must have a non-zero absolute cap on the parent vault.
Otherwise, the buy reverts with `DurationZeroAbsoluteCap`.

### In-kind Redemptions and Enter Gates

A vault shareholder can redeem in-kind from a Midnight market at any time.
To do this, a caller calls `forceDeallocate` on the parent vault with `data` that requests an in-kind redemption for `market` and `taker`.
The `taker` must hold at least one share of the parent vault.
The `taker` must authorize the adapter on Midnight.
The caller of `forceDeallocate` must be `taker` or an address that `taker` authorizes on Midnight.
During `forceDeallocate`, the adapter makes and self-ratifies a reduce-only sell offer at tick `0` (face value) and takes it for `taker`.
The caller pays `assets` plus the Midnight settlement fee to the adapter.
The `taker` receives `assets` of credit in the market.
The adapter moves `assets` to the idle assets of the vault.
The vault then charges its `forceDeallocate` penalty: it burns shares of the `onBehalf` address of the `forceDeallocate` call.

A Midnight market can use an `enterGate` to restrict who can increase credit.
During `forceDeallocate`, such a gate can stop a vault shareholder who wants to receive the credit.
`MidnightAdapterFactory` has the option to use `useGateFactory`.
This option keeps in-kind redemptions possible in gated markets:

- If `useGateFactory` is `true`, the adapter enters a gated market only when all these conditions are true:
  - [VaultV2CompatibleEnterGateFactory](../periphery/gates/VaultV2CompatibleEnterGateFactory.sol) deployed the `enterGate` of the market.
  - The gate authorizes the adapter factory.
  - The `subGate` of the gate allows the adapter to increase credit.
- During `forceDeallocate`, the [VaultV2CompatibleEnterGate](../periphery/gates/VaultV2CompatibleEnterGate.sol) of the market lets `taker` receive the credit, even if the underlying `subGate` does not allow `taker`.
- If `useGateFactory` is `false`, the adapter can enter any gated market. In such a market, `forceDeallocate` works only for takers that the `enterGate` of the market allows.

### Allocator Operational Constraints and Force-sellable Markets

The curator can set non-timelocked operational constraints on the adapter to limit allocator trades:

- **Min net buy rate** (`minNetBuyRate`): Minimum simple net interest rate on buys, relative to paid assets.
- **Max net sell rate** (`maxNetSellRate`): Maximum simple discount rate on sales, relative to sold net credit.
- **No sales with shortfall** (`noSalesWithShortfall`): If `true`, forbids sales with a shortfall.

The curator can set `forceSellable` on a market (timelocked).
For example, use it after maturity: then `ttm` is zero, and rate-based discounts do not allow sales below face value.
When `forceSellable` is `true` for a market:

- The adapter cannot buy credit in that market.
- Sales ignore `maxNetSellRate` and `noSalesWithShortfall`. Instead, each sale must receive at least `minForceSellPrice` per unit of sold net credit.
- The adapter realizes sale losses immediately. It does not decrease `netRate`.

### Timelocks

The adapter has its own timelock system (`submit`, `revoke`, `increaseTimelock`, `decreaseTimelock`, `abdicate`).
This system works like the timelock system in [VaultV2](../VaultV2.sol).
After the timelock of a submitted change expires, anyone can execute the change.
Before the curator adds a `MidnightAdapter` to a vault, it must set the adapter timelocks to match the non-custodial guarantees of the vault.

The timelocked curator functions on the adapter are `increaseTimelock`, `decreaseTimelock`, `abdicate`, `increaseMaxTtm`, `setForceSellable`, and `setSkimRecipient`.
The setters of the operational constraints (`setMinNetBuyRate`, `setMaxNetSellRate`, `setNoSalesWithShortfall`, `setMinForceSellPrice`) are not timelocked.

### Roles

The adapter reads roles directly from its `parentVault`:

- **Curator**:
  - Submits timelocked changes (`increaseMaxTtm`, `setForceSellable`, `setSkimRecipient`, `increaseTimelock`, `decreaseTimelock`, `abdicate`).
  - Revokes pending timelocked changes (`revoke`).
  - Decreases `maxTtm` (`decreaseMaxTtm`) and unsets `forceSellable` (`unsetForceSellable`).
  - Sets the allocator operational constraints (`minNetBuyRate`, `maxNetSellRate`, `noSalesWithShortfall`, `minForceSellPrice`).
- **Allocators**:
  - Call `take`.
  - Withdraw repaid assets to the vault (`deallocate`).
  - Enable or disable [sub-ratifiers](#sub-ratifiers) (`setIsSubRatifier`).
  - Approve Merkle roots on sub-ratifiers and cancel approvals.
  - Set the consumed amounts of offer groups (`setConsumed`).
- **Sentinels**:
  - Revoke pending timelocked changes (`revoke`).
  - Withdraw repaid assets to the vault (`deallocate`).
  - Decrease `maxTtm` (`decreaseMaxTtm`) and unset `forceSellable` (`unsetForceSellable`).
  - Disable sub-ratifiers and cancel approvals of Merkle roots.
  - Increase the consumed amounts of offer groups (`setConsumed`).
