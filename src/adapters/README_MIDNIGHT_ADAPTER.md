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

- The adapter must have the **allocator** role on the parent vault to buy on Midnight.
- To sell on Midnight, the adapter must have the **allocator** or **sentinel** role on the parent vault.
  Sales through `forceDeallocate` do not require these roles.
- The Midnight adapter must not be set as the liquidity adapter of the parent vault. `allocate` accepts only calls from the adapter itself, so vault deposits revert.

The adapter trades in three ways:

- **As a taker**: A vault allocator calls `take` on the adapter to fill an offer on Midnight.
- **As a maker**: Any user on Midnight fills an offer that the adapter made and that an enabled [sub-ratifier](#sub-ratifiers) approved.
- **In-kind redemption**: During `forceDeallocate`, the adapter sells credit to a vault shareholder. See [In-kind Redemptions and Enter Gates](#in-kind-redemptions-and-enter-gates).

While the adapter sells in a market, fills of its maker offers and calls to its `take` function in that market revert.
A sale that absorbs a shortfall also reverts if the adapter is selling in another active market (`OtherSellInProgress`).

On buys, callback data (`takerCallbackData` for takers, `offer.callbackData` for makers) selects the funding source:

- `abi.encode(address(0), "")`: Uses idle assets from the parent vault.
- `abi.encode(fundingAdapter, fundingData)`: Deallocates assets from `fundingAdapter` on the parent vault, then allocates them to the Midnight adapter.
- `abi.encode(address(this), abi.encode(fundingMarket))`: Calls internal `withdrawToVault` for `fundingMarket`, then reports the IDs and net credit change through vault `deallocate`. The vault pulls the withdrawn assets; the adapter calls vault `allocate` to pull them back.

Allocators control the callback data:

- For a taker trade, the allocator who calls `take` sets the callback data.
- For a maker trade, the callback data is part of the offer. A sub-ratifier can constrain the callback data if necessary.

Borrowers repay a market directly or through liquidations, possibly before maturity.
Allocators and sentinels can withdraw the repaid assets to the idle assets of the vault.
To do this, they call `deallocate` on the parent vault with `data = abi.encode(market)`.
`forceDeallocate` sells credit to a shareholder instead; it does not withdraw repaid assets from Midnight.

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

On buys, the adapter adjusts `netRate` to increase amortized value by the paid assets, ignoring rounding.
The adapter rounds rates down on buys and sales that absorb a shortfall, and rounds up each market's shortfall share.
These roundings increase amortized value and can reduce interest by more than the consumed `shortfallAllowance`.

The _shortfall_ of a sale is the sold net credit's amortized value, rounded up, minus the received assets, floored at zero.

- Without a shortfall, `netRate` stays unchanged and the adapter realizes any gain immediately.
- Otherwise, unless the market is [force-sellable](#allocator-operational-constraints-and-force-sellable-markets), the adapter absorbs the shortfall:
  - The sale reverts if the shortfall exceeds `shortfallAllowance` (`ShortfallAllowanceExceeded`) or the remaining interest across markets, calculated after the sale with amortized values rounded up (`ShortfallTooHigh`).
  - The adapter deducts the shortfall from `shortfallAllowance` and reduces each market's remaining unearned interest proportionally, including force-sellable markets.
  - It lowers `netRate` so that, ignoring rounding, its total amortized value decreases only by the received assets.

If a market takes bad debt on Midnight (`lossFactor` changes), `realAssets` immediately uses the reduced net credit.
Loss realization leaves `netRate` unchanged. Both the amortized value and the remaining unearned interest decrease in the same proportion as net credit.

`realAssets` and sales that absorb a shortfall read loss-adjusted net credit and cost more gas as active markets increase.
The vault calls `realAssets` at interest accrual, so this also affects most vault operations.

### Caps and Duration Caps

On each allocation and deallocation, the adapter reports the change in stored `netCredit` to the cap system of the parent vault for these market IDs (`ids(market)`):

- Adapter
- Family: the ordered collateral configurations (`collateralParams`), RCF threshold, and liquidator gate
- Each collateral token

The adapter can buy credit in a market only if each of these IDs has a non-zero absolute cap on the parent vault.
The curator uses family caps to approve combinations, not individual parameters.
Markets that differ only by maturity or enter gate share the same family ID.

To limit maturity risk, the adapter has up to 8 strictly increasing durations (`durations`).
These durations are set at deployment.
The adapter also applies a global `maxTtm` limit on buys.
Each duration `d` caps the credit in markets that mature `d` or more from now.
The total stored `netCredit` of these markets must stay within the absolute and relative caps of the duration ID of `d` on the parent vault.
For example, with durations of 30 and 90 days, only the 30-day caps limit the credit in a market that matures in 60 days. When the market is less than 30 days from maturity, no duration cap limits its credit.
The adapter checks these caps on every buy.
The parent vault stores the caps, and the adapter calculates the allocations.
The parent vault reverts a deallocation if one of the market IDs has zero allocation (`ZeroAllocation`). The adapter does not apply this check to duration IDs.

For a buy, every configured duration up to the remaining time to maturity of the market must have a non-zero absolute cap on the parent vault.
Otherwise, the buy reverts with `DurationZeroAbsoluteCap`.

### In-kind Redemptions and Enter Gates

A vault shareholder can redeem in-kind from a Midnight market at any time.
To do this, a caller calls `forceDeallocate` on the parent vault with `data` that requests an in-kind redemption for `market` and `taker`.
The `taker` must hold at least one share of the parent vault.
The `taker` must authorize the adapter on Midnight.
The caller of `forceDeallocate` must be `taker` or an address that `taker` authorizes on Midnight.
During `forceDeallocate`, the adapter transfers `assets` plus the Midnight settlement fee from the caller to itself.
The adapter then takes its own reduce-only sell offer for `taker` at tick `0` (zero price).
During this trade, the adapter ratifies the offer itself.
The `taker` receives `assets` of credit in the market.
The adapter moves `assets` to the idle assets of the vault.
The vault then charges its `forceDeallocate` penalty: it burns shares of the `onBehalf` address of the `forceDeallocate` call.

A Midnight market can use an `enterGate` to restrict who can increase credit.
During `forceDeallocate`, such a gate can stop a vault shareholder who wants to receive the credit.
`MidnightAdapterFactory.createMidnightAdapter` accepts an `enterGateFactory` address.
You can use [VaultV2CompatibleEnterGateFactory](../periphery/gates/VaultV2CompatibleEnterGateFactory.sol) for this parameter.

- If `enterGateFactory != address(0)`, the adapter enters a gated market only when all these conditions are true:
  - `enterGateFactory.isCreated(market.enterGate)` returns `true`.
  - The gate authorizes the adapter factory.
  - The `subGate` of the gate allows the adapter to increase credit.
- During `forceDeallocate`, the adapter calls `admit` on the gate if the configured factory created it.
  The [VaultV2CompatibleEnterGate](../periphery/gates/VaultV2CompatibleEnterGate.sol) then lets `taker` receive credit even if `subGate` does not allow `taker`.
- If `enterGateFactory == address(0)`, the adapter does not check which factory created the gate.
  `forceDeallocate` then works only if the market's `enterGate` allows `taker`.

### Allocator Operational Constraints and Force-sellable Markets

The curator can set non-timelocked operational constraints on the adapter to limit allocator trades:

- **Min net buy rate** (`minNetBuyRate`): Minimum simple net interest rate on buys, relative to paid assets.
- **Max net sell rate** (`maxNetSellRate`): Maximum simple net interest rate on sales. The rate is relative to the assets that the adapter receives.
- **Shortfall allowance** (`shortfallAllowance`): Remaining asset-denominated shortfall budget across markets. It starts at zero and does not refill automatically.

A sale can consume the old allowance before `setShortfallAllowance` replaces it. Set it to zero first, then set the new value after checking consumption.

The curator can set `forceSellable` on a market (timelocked).
For example, use it after maturity: then `ttm` is zero, and rate-based discounts do not allow sales below face value.
When `forceSellable` is `true` for a market:

- The adapter cannot buy credit in that market.
- Sales ignore `maxNetSellRate` and do not consume `shortfallAllowance`. Instead, each sale must receive at least `minForceSellPrice` per unit of sold net credit.
- The adapter realizes sale losses immediately, without decreasing any market's `netRate`.

### Timelocks

The adapter has its own timelock system (`submit`, `revoke`, `increaseTimelock`, `decreaseTimelock`, `abdicate`).
This system works like the timelock system in [VaultV2](../VaultV2.sol), but `submit` rejects data longer than 68 bytes (`DataTooLong`).
After the timelock of a submitted change expires, anyone can execute the change.
Before the curator adds a `MidnightAdapter` to a vault, it must set the adapter timelocks to match the non-custodial guarantees of the vault.
The curator must also check that no unsafe actions are pending.
Calling `increaseTimelock` does not change the adapter's `executableAt` values for pending actions.

The timelocked curator functions on the adapter are `increaseTimelock`, `decreaseTimelock`, `abdicate`, `increaseMaxTtm`, `setForceSellable`, and `setSkimRecipient`.
The setters of the operational constraints (`setMinNetBuyRate`, `setMaxNetSellRate`, `setShortfallAllowance`, `setMinForceSellPrice`) are not timelocked.

### Roles

The adapter reads roles directly from its `parentVault`:

- **Curator**:
  - Submits timelocked changes (`increaseMaxTtm`, `setForceSellable`, `setSkimRecipient`, `increaseTimelock`, `decreaseTimelock`, `abdicate`).
  - Revokes pending timelocked changes (`revoke`).
  - Decreases `maxTtm` (`decreaseMaxTtm`) and unsets `forceSellable` (`unsetForceSellable`).
  - Sets the allocator operational constraints (`minNetBuyRate`, `maxNetSellRate`, `shortfallAllowance`, `minForceSellPrice`).
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
