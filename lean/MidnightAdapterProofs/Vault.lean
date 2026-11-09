import MidnightAdapterProofs.Operations

/-!
# Buys and sells don't decrease the vault's share price

`VaultV2.accrueInterestView` with the MidnightAdapter as the only adapter, no performance fee and
no management fee. `_totalAssets`, `totalSupply` and `virtualShares` are left unchanged by
`allocate`/`deallocate` (the trade's own accrual runs on the pre-trade state, through
`inProgressBuy*` on buys), so the trade only changes `realAssets`. The theorems compare the vault's
share price after the trade with the share price without it, at the trade's timestamp: each market's
`ttm` is the one the trade used. Later accruals re-discount at a smaller `ttm`, and rate rounding can
then leave the traded state a few units of assets below the untraded one; that isn't covered.
-/

namespace MidnightAdapterProofs

open Finset

variable {ι : Type*} [Fintype ι] [DecidableEq ι]

/-- The vault's stored accounting: `_totalAssets`, `totalSupply`, `virtualShares`, `maxRate`, and
the time elapsed since `lastUpdate`. -/
structure Vault where
  totalAssets : ℕ
  totalSupply : ℕ
  virtualShares : ℕ
  maxRate : ℕ
  elapsed : ℕ

/-- `newTotalAssets` in `accrueInterestView`, for a vault whose real assets are `realAssets`. -/
def newTotalAssets (v : Vault) (realAssets : ℕ) : ℕ :=
  min realAssets (v.totalAssets + mulDivDown (v.totalAssets * v.elapsed) v.maxRate WAD)

/-- `previewRedeem` (and `convertToAssets`) without fees. -/
def previewRedeem (v : Vault) (realAssets shares : ℕ) : ℕ :=
  mulDivDown shares (newTotalAssets v realAssets + 1) (v.totalSupply + v.virtualShares)

/-- `previewDeposit` (and `convertToShares`) without fees. -/
def previewDeposit (v : Vault) (realAssets assets : ℕ) : ℕ :=
  mulDivDown assets (v.totalSupply + v.virtualShares) (newTotalAssets v realAssets + 1)

lemma previewRedeem_mono (v : Vault) {r r' : ℕ} (h : r ≤ r') (shares : ℕ) :
    previewRedeem v r shares ≤ previewRedeem v r' shares := by
  unfold previewRedeem mulDivDown newTotalAssets
  apply Nat.div_le_div_right
  apply Nat.mul_le_mul_left
  omega

lemma previewDeposit_anti (v : Vault) {r r' : ℕ} (h : r ≤ r') (assets : ℕ) :
    previewDeposit v r' assets ≤ previewDeposit v r assets := by
  unfold previewDeposit mulDivDown newTotalAssets
  apply Nat.div_le_div_left _ (by omega)
  omega

/-- A share redeems for at least as many assets after a buy funded from idle assets. -/
theorem sharePrice_buy (v : Vault) (s : State ι) (m : ι) (buyerAssets boughtNetCredit shares : ℕ)
    (hBuyAtLoss : buyerAssets ≤ boughtNetCredit) (hIdle : buyerAssets ≤ s.idle) :
    previewRedeem v (realAssets s) shares ≤
      previewRedeem v (realAssets (buy s m buyerAssets boughtNetCredit)) shares :=
  previewRedeem_mono v (realAssets_buy s m buyerAssets boughtNetCredit hBuyAtLoss hIdle) shares

/-- A share redeems for at least as many assets after a self-funded buy. -/
theorem sharePrice_selfFundedBuy (v : Vault) (s : State ι) (m fundingMarket : ι)
    (buyerAssets boughtNetCredit shares : ℕ) (hBuyAtLoss : buyerAssets ≤ boughtNetCredit)
    (hWithdrawable : buyerAssets ≤ (recordBuy s m buyerAssets boughtNetCredit).credit fundingMarket) :
    previewRedeem v (realAssets s) shares ≤
      previewRedeem v (realAssets (selfFundedBuy s m fundingMarket buyerAssets boughtNetCredit))
        shares :=
  previewRedeem_mono v
    (realAssets_selfFundedBuy s m fundingMarket buyerAssets boughtNetCredit hBuyAtLoss
      hWithdrawable) shares

/-- A share redeems for at least as many assets after a sale in a market that isn't
forceSellable. -/
theorem sharePrice_sell (v : Vault) (s : State ι) (m : ι) (sellerAssets soldNetCredit shares : ℕ)
    (hSold : soldNetCredit ≤ s.credit m)
    (hShortfall : let netCredit := Function.update s.credit m (s.credit m - soldNetCredit)
      shortfall s m sellerAssets soldNetCredit
        ≤ ∑ i, (netCredit i - value (netCredit i) (s.rate i) (s.ttm i))) :
    previewRedeem v (realAssets s) shares ≤
      previewRedeem v (realAssets (sell s m sellerAssets soldNetCredit)) shares :=
  previewRedeem_mono v (realAssets_sell s m sellerAssets soldNetCredit hSold hShortfall) shares

/-- Depositing after a buy mints at most as many shares. -/
theorem previewDeposit_buy (v : Vault) (s : State ι) (m : ι) (buyerAssets boughtNetCredit assets : ℕ)
    (hBuyAtLoss : buyerAssets ≤ boughtNetCredit) (hIdle : buyerAssets ≤ s.idle) :
    previewDeposit v (realAssets (buy s m buyerAssets boughtNetCredit)) assets ≤
      previewDeposit v (realAssets s) assets :=
  previewDeposit_anti v (realAssets_buy s m buyerAssets boughtNetCredit hBuyAtLoss hIdle) assets

/-- Depositing after a sale mints at most as many shares. -/
theorem previewDeposit_sell (v : Vault) (s : State ι) (m : ι)
    (sellerAssets soldNetCredit assets : ℕ) (hSold : soldNetCredit ≤ s.credit m)
    (hShortfall : let netCredit := Function.update s.credit m (s.credit m - soldNetCredit)
      shortfall s m sellerAssets soldNetCredit
        ≤ ∑ i, (netCredit i - value (netCredit i) (s.rate i) (s.ttm i))) :
    previewDeposit v (realAssets (sell s m sellerAssets soldNetCredit)) assets ≤
      previewDeposit v (realAssets s) assets :=
  previewDeposit_anti v (realAssets_sell s m sellerAssets soldNetCredit hSold hShortfall) assets

end MidnightAdapterProofs
