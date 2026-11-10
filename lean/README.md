# Lean proofs

Proofs that, in a VaultV2 whose only adapter is a MidnightAdapter, with no bad debt and no
performance or management fee, buys and sales outside forceSellable markets don't decrease the
share price at the time of the trade. The comparison is at the trade's timestamp: once time passes,
rate rounding can leave the traded state a few units of assets below the untraded one.

- `Model.lean`: modelling scope and definitions for the adapter's valuation, trades and vault accounting.
- `Lemmas.lean`: arithmetic, projection and real-assets lemmas, and preview monotonicity.
- `Theorems.lean`: the final vault share-price and deposit-preview results.

To review, read `Model.lean` and the statements in `Theorems.lean`.

```sh
cd lean
lake exe cache get
lake build
```
