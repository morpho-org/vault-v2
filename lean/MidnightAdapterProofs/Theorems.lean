import MidnightAdapterProofs.Lemmas

/-!
# Vault share price results

To review the model and guarantees, read `Model.lean` and the theorem statements here.
-/

namespace MidnightAdapterProofs

open Finset

variable {ι : Type*} [Fintype ι] [DecidableEq ι]

/-- A share redeems for at least as many assets after a buy funded from idle assets. -/
theorem sharePrice_buy (v : Vault) (s : State ι) (m : ι) (buyerAssets boughtNetCredit shares : ℕ)
    (hBuyAtLoss : buyerAssets ≤ boughtNetCredit) (hIdle : buyerAssets ≤ s.idle) :
    previewRedeem v (realAssets s) shares ≤
      previewRedeem v (realAssets (buy s m buyerAssets boughtNetCredit)) shares :=
  previewRedeem_mono v (realAssets_buy s m buyerAssets boughtNetCredit hBuyAtLoss hIdle) shares

/-- A share redeems for at least as many assets after a self-funded buy. -/
theorem sharePrice_selfFundedBuy (v : Vault) (s : State ι) (m fundingMarket : ι)
    (buyerAssets boughtNetCredit shares : ℕ) (hBuyAtLoss : buyerAssets ≤ boughtNetCredit)
    (hWithdrawable : buyerAssets ≤ (recordBuy s m buyerAssets boughtNetCredit).netCredit fundingMarket) :
    previewRedeem v (realAssets s) shares ≤
      previewRedeem v (realAssets (selfFundedBuy s m fundingMarket buyerAssets boughtNetCredit))
        shares :=
  previewRedeem_mono v
    (realAssets_selfFundedBuy s m fundingMarket buyerAssets boughtNetCredit hBuyAtLoss
      hWithdrawable) shares

/-- A share redeems for at least as many assets after a sale in a market that isn't
forceSellable. -/
theorem sharePrice_sell [LinearOrder ι] (v : Vault) (s : State ι) (m : ι) (sellerAssets soldNetCredit shares : ℕ)
    (hSold : soldNetCredit ≤ s.netCredit m)
    (hShortfall : let netCredit := Function.update s.netCredit m (s.netCredit m - soldNetCredit)
      shortfall s m sellerAssets soldNetCredit
        ≤ ∑ i, (netCredit i - amortizedValue (netCredit i) (s.netRate i) (s.ttm i))) :
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
theorem previewDeposit_sell [LinearOrder ι] (v : Vault) (s : State ι) (m : ι)
    (sellerAssets soldNetCredit assets : ℕ) (hSold : soldNetCredit ≤ s.netCredit m)
    (hShortfall : let netCredit := Function.update s.netCredit m (s.netCredit m - soldNetCredit)
      shortfall s m sellerAssets soldNetCredit
        ≤ ∑ i, (netCredit i - amortizedValue (netCredit i) (s.netRate i) (s.ttm i))) :
    previewDeposit v (realAssets (sell s m sellerAssets soldNetCredit)) assets ≤
      previewDeposit v (realAssets s) assets :=
  previewDeposit_anti v (realAssets_sell s m sellerAssets soldNetCredit hSold hShortfall) assets

end MidnightAdapterProofs
