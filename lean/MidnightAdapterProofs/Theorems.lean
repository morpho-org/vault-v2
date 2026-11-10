import MidnightAdapterProofs.Lemmas

/-!
# Vault share price results

To review the model and guarantees, read `Model.lean` and the theorem statements here.
-/

namespace MidnightAdapterProofs

open Finset

variable {ι : Type*} [Fintype ι] [DecidableEq ι]

/-- A buy funded from idle assets doesn't decrease the share price. -/
theorem sharePrice_buy (s : State ι) (m : ι) (buyerAssets boughtNetCredit : ℕ)
    (hBuyAtLoss : buyerAssets ≤ boughtNetCredit) (hIdle : buyerAssets ≤ s.idle) :
    sharePrice s ≤
      sharePrice (buy s m buyerAssets boughtNetCredit) :=
  sharePrice_accrued (realAssets_buy s m buyerAssets boughtNetCredit hBuyAtLoss hIdle) rfl rfl rfl

/-- A self-funded buy doesn't decrease the share price. -/
theorem sharePrice_selfFundedBuy (s : State ι) (m fundingMarket : ι)
    (buyerAssets boughtNetCredit : ℕ) (hBuyAtLoss : buyerAssets ≤ boughtNetCredit)
    (hWithdrawable : buyerAssets ≤ (recordBuy s m buyerAssets boughtNetCredit).netCredit fundingMarket) :
    sharePrice s ≤
      sharePrice (selfFundedBuy s m fundingMarket buyerAssets boughtNetCredit) :=
  sharePrice_accrued
    (realAssets_selfFundedBuy s m fundingMarket buyerAssets boughtNetCredit hBuyAtLoss
      hWithdrawable) rfl rfl rfl

/-- A sale in a market that isn't forceSellable doesn't decrease the share price. -/
theorem sharePrice_sell [LinearOrder ι] (s : State ι) (m : ι) (sellerAssets soldNetCredit : ℕ)
    (hSold : soldNetCredit ≤ s.netCredit m)
    (hShortfall : let netCredit := Function.update s.netCredit m (s.netCredit m - soldNetCredit)
      shortfall s m sellerAssets soldNetCredit
        ≤ ∑ i, (netCredit i - amortizedValue (netCredit i) (s.netRate i) (s.ttm i))) :
    sharePrice s ≤
      sharePrice (sell s m sellerAssets soldNetCredit) :=
  sharePrice_mono (realAssets_sell s m sellerAssets soldNetCredit hSold hShortfall) rfl rfl

/-- Withdrawing credit to the vault doesn't decrease the share price. -/
theorem sharePrice_withdraw (s : State ι) (m : ι) (assets : ℕ)
    (hWithdrawable : assets ≤ s.netCredit m) :
    sharePrice s ≤
      sharePrice (withdraw s m assets) :=
  sharePrice_mono (realAssets_withdraw s m assets hWithdrawable) rfl rfl

/-- Force deallocation, including accrual and the penalty exit, doesn't decrease the share price.
Any extra liquidity withdrawal is assumed to preserve real assets as specified by `penaltyExit`. -/
theorem sharePrice_forceDeallocate (s : State ι) (m : ι)
    (assets soldNetCredit penalty : ℕ)
    (hSold : soldNetCredit ≤ s.netCredit m) (hAssets : soldNetCredit ≤ assets)
    (hVirtual : 0 < s.virtualShares)
    (hPenalty : penalty ≤ newTotalAssets (recordForceDeallocate s m assets soldNetCredit))
    (hShares : previewWithdraw (recordForceDeallocate s m assets soldNetCredit) penalty
      ≤ s.totalSupply) :
    sharePrice s ≤ sharePrice (forceDeallocate s m assets soldNetCredit penalty) := by
  exact le_trans
    (sharePrice_mono
      (realAssets_recordForceDeallocate s m assets soldNetCredit hSold hAssets) rfl rfl)
    (sharePrice_penaltyExit _ penalty hVirtual hPenalty hShares)

end MidnightAdapterProofs
