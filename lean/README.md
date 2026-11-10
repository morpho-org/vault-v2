# Lean proofs

Proofs that, in a VaultV2 whose only adapter is a MidnightAdapter, with no bad debt and no performance or management fee, buys, withdrawals, force deallocations and sales outside forceSellable markets don't decrease the share price at the time of the operation.
Each operation has a deposit-preview counterpart.
Force deallocation includes the vault's penalty-share burn, assuming any extra liquidity withdrawal preserves real assets.
The comparison is at the trade's timestamp: once time passes, rate rounding can leave the traded state a few units of assets below the untraded one.

- `Model.lean`: modelling scope and definitions for the adapter's valuation, trades and vault accounting.
- `Lemmas.lean`: arithmetic, projection and real-assets lemmas, and preview monotonicity.
- `Theorems.lean`: the final vault share-price and deposit-preview results.
