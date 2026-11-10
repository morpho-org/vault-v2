# Lean proofs

Proofs that, in a VaultV2 whose only adapter is a MidnightAdapter, with no bad debt and no performance or management fee, buys, withdrawals, force deallocations and sales outside forceSellable markets don't decrease the share price at the time of the operation.
The comparison uses the unrounded rational share price.
The proofs cover operations that perform the transaction's first vault accrual.
If the vault has already accrued earlier in the same transaction (`firstTotalAssets != 0`), `accrueInterestView` returns the cached `_totalAssets`, and that case is not modeled.
One state contains the vault accounting, its idle balance and the adapter's market data.
Buys accrue against the pre-buy valuation, while force deallocation accrues after pulling assets into the vault.
Sales and ordinary adapter withdrawals do not accrue.
The rounded `previewRedeem` and `previewDeposit` are floors of an amount times this ratio and its inverse, so redemption previews increase and deposit previews decrease with the price.
Force deallocation includes accrual and the vault's penalty-share burn, assuming any extra liquidity withdrawal preserves real assets.
The comparison is at the trade's timestamp: once time passes, rate rounding can leave the traded state a few units of assets below the untraded one.

- `Model.lean`: modelling scope and definitions for the adapter's valuation, trades and vault accounting.
- `Lemmas.lean`: arithmetic, projection and real-assets lemmas, and share-price monotonicity.
- `Theorems.lean`: the five vault share-price statements, defined as propositions without proofs.
- `Proofs.lean`: proofs of the five propositions.

To review the model and guarantees, read only `Model.lean` and `Theorems.lean`.
