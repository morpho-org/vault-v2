# Lean proofs

Proofs that, in a VaultV2 whose only adapter is a MidnightAdapter and with no bad debt, buys and
sales outside forceSellable markets don't decrease the share price.

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
