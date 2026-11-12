import MidnightAdapterProofs.Lemmas
import MidnightAdapterProofs.Theorems

namespace MidnightAdapterProofs

variable {ι : Type*} [Fintype ι] [DecidableEq ι]

theorem buy_forceRemoved (s : State ι) (m : ι) (a b : ℕ)
    (h : s.forceRemoved m = true) : buy s m a b = none := by
  simp [buy, h]

theorem withdraw_forceRemoved (s : State ι) (m : ι) (a : ℕ)
    (h : s.forceRemoved m = true) : withdraw s m a = none := by
  simp [withdraw, h]

theorem selfFundedBuy_forceRemoved (s : State ι) (m f : ι) (a b : ℕ)
    (h : s.forceRemoved m = true) : selfFundedBuy s m f a b = none := by
  simp [selfFundedBuy, h]

theorem selfFundedBuy_fundingForceRemoved (s : State ι) (m f : ι) (a b : ℕ)
    (h : s.forceRemoved f = true) : selfFundedBuy s m f a b = none := by
  unfold selfFundedBuy
  split_ifs <;> simp [withdraw, recordBuy, h]

theorem sell_forceRemoved [LinearOrder ι] (s : State ι) (m : ι) (a b : ℕ)
    (h : s.forceRemoved m = true) : sell s m a b = none := by
  simp [sell, h]

theorem forceDeallocate_forceRemoved (s : State ι) (m : ι) (a b p : ℕ)
    (h : s.forceRemoved m = true) : forceDeallocate s m a b p = none := by
  simp [forceDeallocate, h]

theorem sharePriceBuy : SharePriceBuy (ι := ι) := by
  intro s m buyerAssets boughtNetCredit s' hSuccess
  unfold buy at hSuccess
  split_ifs at hSuccess with h
  · cases hSuccess
    exact sharePrice_accrued
      (realAssets_buy s m buyerAssets boughtNetCredit h.2.1 h.2.2) rfl rfl rfl

theorem sharePriceSelfFundedBuy : SharePriceSelfFundedBuy (ι := ι) := by
  intro s m fundingMarket buyerAssets boughtNetCredit s' hSuccess
  unfold selfFundedBuy at hSuccess
  split_ifs at hSuccess with hBuyAtLoss
  · unfold withdraw at hSuccess
    split_ifs at hSuccess with hWithdrawable
    · cases hSuccess
      exact sharePrice_accrued
        (realAssets_selfFundedBuy s m fundingMarket buyerAssets boughtNetCredit hBuyAtLoss.2
          hWithdrawable.2) rfl rfl rfl
    · cases hSuccess

theorem sharePriceSell [LinearOrder ι] : SharePriceSell (ι := ι) := by
  intro s m sellerAssets soldNetCredit s' hSuccess
  unfold sell at hSuccess
  dsimp only at hSuccess
  split_ifs at hSuccess with h
  · cases hSuccess
    exact sharePrice_mono
      (realAssets_sell s m sellerAssets soldNetCredit h.2.1 h.2.2) rfl rfl

theorem sharePriceWithdraw : SharePriceWithdraw (ι := ι) := by
  intro s m assets s' hSuccess
  unfold withdraw at hSuccess
  split_ifs at hSuccess with hWithdrawable
  · cases hSuccess
    exact sharePrice_mono (realAssets_withdraw s m assets hWithdrawable.2) rfl rfl

theorem sharePriceForceDeallocate : SharePriceForceDeallocate (ι := ι) := by
  intro s m assets soldNetCredit penalty s' hSuccess hSoldLessThanAssets hPositiveVirtualShares
  unfold forceDeallocate at hSuccess
  split_ifs at hSuccess with hSold
  · unfold penaltyExit at hSuccess
    split_ifs at hSuccess with h
    · cases hSuccess
      exact le_trans
        (sharePrice_mono
          (realAssets_recordForceDeallocate s m assets soldNetCredit hSold.2 hSoldLessThanAssets)
          rfl rfl)
        (sharePrice_penaltyExit _ penalty hPositiveVirtualShares h.1 h.2)

end MidnightAdapterProofs
