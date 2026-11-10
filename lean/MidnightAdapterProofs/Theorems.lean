import MidnightAdapterProofs.Lemmas

/-!
# Vault share price results

To review the model and guarantees, read `Model.lean` and the theorem statements here.
-/

namespace MidnightAdapterProofs

open Finset

variable {ι : Type*} [Fintype ι] [DecidableEq ι]

/-- A buy funded from idle assets doesn't decrease the share price. -/
theorem sharePrice_buy (v : Vault) (s : State ι) (m : ι) (buyerAssets boughtNetCredit : ℕ)
    (hBuyAtLoss : buyerAssets ≤ boughtNetCredit) (hIdle : buyerAssets ≤ s.idle) :
    sharePrice v (realAssets s) ≤
      sharePrice v (realAssets (buy s m buyerAssets boughtNetCredit)) :=
  sharePrice_mono v (realAssets_buy s m buyerAssets boughtNetCredit hBuyAtLoss hIdle)

/-- A self-funded buy doesn't decrease the share price. -/
theorem sharePrice_selfFundedBuy (v : Vault) (s : State ι) (m fundingMarket : ι)
    (buyerAssets boughtNetCredit : ℕ) (hBuyAtLoss : buyerAssets ≤ boughtNetCredit)
    (hWithdrawable : buyerAssets ≤ (recordBuy s m buyerAssets boughtNetCredit).netCredit fundingMarket) :
    sharePrice v (realAssets s) ≤
      sharePrice v (realAssets (selfFundedBuy s m fundingMarket buyerAssets boughtNetCredit)) :=
  sharePrice_mono v
    (realAssets_selfFundedBuy s m fundingMarket buyerAssets boughtNetCredit hBuyAtLoss
      hWithdrawable)

/-- A sale in a market that isn't forceSellable doesn't decrease the share price. -/
theorem sharePrice_sell [LinearOrder ι] (v : Vault) (s : State ι) (m : ι) (sellerAssets soldNetCredit : ℕ)
    (hSold : soldNetCredit ≤ s.netCredit m)
    (hShortfall : let netCredit := Function.update s.netCredit m (s.netCredit m - soldNetCredit)
      shortfall s m sellerAssets soldNetCredit
        ≤ ∑ i, (netCredit i - amortizedValue (netCredit i) (s.netRate i) (s.ttm i))) :
    sharePrice v (realAssets s) ≤
      sharePrice v (realAssets (sell s m sellerAssets soldNetCredit)) :=
  sharePrice_mono v (realAssets_sell s m sellerAssets soldNetCredit hSold hShortfall)

/-- Withdrawing credit to the vault doesn't decrease the share price. -/
theorem sharePrice_withdraw (v : Vault) (s : State ι) (m : ι) (assets : ℕ)
    (hWithdrawable : assets ≤ s.netCredit m) :
    sharePrice v (realAssets s) ≤
      sharePrice v (realAssets (withdraw s m assets)) :=
  sharePrice_mono v (realAssets_withdraw s m assets hWithdrawable)

/-- Force deallocation and the penalty exit don't decrease the share price.
Any extra liquidity withdrawal is assumed to preserve real assets as specified by `penaltyExit`. -/
theorem sharePrice_forceDeallocate (v : Vault) (s : State ι) (m : ι)
    (assets soldNetCredit penalty : ℕ)
    (hSold : soldNetCredit ≤ s.netCredit m) (hAssets : soldNetCredit ≤ assets)
    (hVirtual : 0 < v.virtualShares)
    (hPenalty : penalty ≤ newTotalAssets v (realAssets (forceDeallocate s m assets soldNetCredit)))
    (hShares : previewWithdraw v (realAssets (forceDeallocate s m assets soldNetCredit)) penalty
      ≤ v.totalSupply) :
    sharePrice v (realAssets s) ≤
      sharePrice
        (penaltyExit v (realAssets (forceDeallocate s m assets soldNetCredit)) penalty)
        (realAssets (forceDeallocate s m assets soldNetCredit)) := by
  exact le_trans
    (sharePrice_mono v (realAssets_forceDeallocate s m assets soldNetCredit hSold hAssets))
    (sharePrice_penaltyExit v _ penalty hVirtual hPenalty hShares)

end MidnightAdapterProofs
