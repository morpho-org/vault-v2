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

/-- A share redeems for at least as many assets after withdrawing credit to the vault. -/
theorem sharePrice_withdraw (v : Vault) (s : State ι) (m : ι) (assets shares : ℕ)
    (hWithdrawable : assets ≤ s.netCredit m) :
    previewRedeem v (realAssets s) shares ≤
      previewRedeem v (realAssets (withdraw s m assets)) shares :=
  previewRedeem_mono v (realAssets_withdraw s m assets hWithdrawable) shares

/-- Depositing after withdrawing credit to the vault mints at most as many shares. -/
theorem previewDeposit_withdraw (v : Vault) (s : State ι) (m : ι) (assets depositAssets : ℕ)
    (hWithdrawable : assets ≤ s.netCredit m) :
    previewDeposit v (realAssets (withdraw s m assets)) depositAssets ≤
      previewDeposit v (realAssets s) depositAssets :=
  previewDeposit_anti v (realAssets_withdraw s m assets hWithdrawable) depositAssets

/-- Depositing after a self-funded buy mints at most as many shares. -/
theorem previewDeposit_selfFundedBuy (v : Vault) (s : State ι) (m fundingMarket : ι)
    (buyerAssets boughtNetCredit assets : ℕ) (hBuyAtLoss : buyerAssets ≤ boughtNetCredit)
    (hWithdrawable : buyerAssets ≤ (recordBuy s m buyerAssets boughtNetCredit).netCredit fundingMarket) :
    previewDeposit v (realAssets (selfFundedBuy s m fundingMarket buyerAssets boughtNetCredit)) assets ≤
      previewDeposit v (realAssets s) assets :=
  previewDeposit_anti v
    (realAssets_selfFundedBuy s m fundingMarket buyerAssets boughtNetCredit hBuyAtLoss
      hWithdrawable) assets

/-- A share redeems for at least as many assets after force deallocation and the penalty exit.
Any extra liquidity withdrawal is assumed to preserve real assets as specified by `penaltyExit`. -/
theorem sharePrice_forceDeallocate (v : Vault) (s : State ι) (m : ι)
    (assets soldNetCredit penalty shares : ℕ)
    (hSold : soldNetCredit ≤ s.netCredit m) (hAssets : soldNetCredit ≤ assets)
    (hVirtual : 0 < v.virtualShares)
    (hPenalty : penalty ≤ newTotalAssets v (realAssets (forceDeallocate s m assets soldNetCredit)))
    (hShares : previewWithdraw v (realAssets (forceDeallocate s m assets soldNetCredit)) penalty
      ≤ v.totalSupply) :
    previewRedeem v (realAssets s) shares ≤
      previewRedeem
        (penaltyExit v (realAssets (forceDeallocate s m assets soldNetCredit)) penalty)
        (realAssets (forceDeallocate s m assets soldNetCredit)) shares := by
  exact le_trans
    (previewRedeem_mono v (realAssets_forceDeallocate s m assets soldNetCredit hSold hAssets) shares)
    (previewRedeem_penaltyExit v _ penalty shares hVirtual hPenalty hShares)

/-- Depositing after force deallocation and the penalty exit mints at most as many shares.
Any extra liquidity withdrawal is assumed to preserve real assets as specified by `penaltyExit`. -/
theorem previewDeposit_forceDeallocate (v : Vault) (s : State ι) (m : ι)
    (assets soldNetCredit penalty depositAssets : ℕ)
    (hSold : soldNetCredit ≤ s.netCredit m) (hAssets : soldNetCredit ≤ assets)
    (hPenalty : penalty ≤ newTotalAssets v (realAssets (forceDeallocate s m assets soldNetCredit)))
    (hShares : previewWithdraw v (realAssets (forceDeallocate s m assets soldNetCredit)) penalty
      ≤ v.totalSupply) :
    previewDeposit
        (penaltyExit v (realAssets (forceDeallocate s m assets soldNetCredit)) penalty)
        (realAssets (forceDeallocate s m assets soldNetCredit)) depositAssets ≤
      previewDeposit v (realAssets s) depositAssets := by
  exact le_trans
    (previewDeposit_penaltyExit v _ penalty depositAssets hPenalty hShares)
    (previewDeposit_anti v
      (realAssets_forceDeallocate s m assets soldNetCredit hSold hAssets) depositAssets)

end MidnightAdapterProofs
