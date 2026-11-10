import MidnightAdapterProofs.Lemmas
import MidnightAdapterProofs.Theorems

namespace MidnightAdapterProofs

variable {ι : Type*} [Fintype ι] [DecidableEq ι]

theorem sharePriceBuy : SharePriceBuy (ι := ι) := by
  intro s m buyerAssets boughtNetCredit hBuyAtLoss hIdle
  exact sharePrice_accrued
    (realAssets_buy s m buyerAssets boughtNetCredit hBuyAtLoss hIdle) rfl rfl rfl

theorem sharePriceSelfFundedBuy : SharePriceSelfFundedBuy (ι := ι) := by
  intro s m fundingMarket buyerAssets boughtNetCredit hBuyAtLoss hWithdrawable
  exact sharePrice_accrued
    (realAssets_selfFundedBuy s m fundingMarket buyerAssets boughtNetCredit hBuyAtLoss
      hWithdrawable) rfl rfl rfl

theorem sharePriceSell [LinearOrder ι] : SharePriceSell (ι := ι) := by
  intro s m sellerAssets soldNetCredit hSold hShortfall
  exact sharePrice_mono
    (realAssets_sell s m sellerAssets soldNetCredit hSold hShortfall) rfl rfl

theorem sharePriceWithdraw : SharePriceWithdraw (ι := ι) := by
  intro s m assets hWithdrawable
  exact sharePrice_mono (realAssets_withdraw s m assets hWithdrawable) rfl rfl

theorem sharePriceForceDeallocate : SharePriceForceDeallocate (ι := ι) := by
  intro s m assets soldNetCredit penalty hSold hAssets hVirtual hPenalty hShares
  exact le_trans
    (sharePrice_mono
      (realAssets_recordForceDeallocate s m assets soldNetCredit hSold hAssets) rfl rfl)
    (sharePrice_penaltyExit _ penalty hVirtual hPenalty hShares)

end MidnightAdapterProofs
