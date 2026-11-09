# Lean proofs

Proofs that, in a VaultV2 whose only adapter is a MidnightAdapter, with no bad debt and no
performance or management fee, buys and sales outside forceSellable markets don't decrease the
share price at the time of the trade. The comparison is at the trade's timestamp: once time passes,
rate rounding can leave the traded state a few units of assets below the untraded one.

- `Basic.lean`: rounding lemmas for the adapter's valuation `netCredit * WAD / (WAD + netRate * ttm)`.
- `Operations.lean`: `onBuy` (funded from idle assets or self-funded), `withdrawToVault` and
  `onSell` with shortfall, and the theorems that they don't decrease the vault's real assets.
- `Vault.lean`: `accrueInterestView`, `previewRedeem` and `previewDeposit` without fees, and the
  share price theorems.

```sh
cd lean
lake exe cache get
lake build
```
