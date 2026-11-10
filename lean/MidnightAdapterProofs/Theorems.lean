import MidnightAdapterProofs.Model

/-!
# Vault share price statements

To review the model and guarantees, read only `Model.lean` and `Theorems.lean`.
The proofs of these propositions are in `Proofs.lean`.
-/

namespace MidnightAdapterProofs

open Finset

variable {ι : Type*} [Fintype ι] [DecidableEq ι]

/-- A buy funded from idle assets doesn't decrease the share price. -/
def SharePriceBuy : Prop :=
  ∀ (s : State ι) (m : ι) (buyerAssets boughtNetCredit : ℕ),
    (hBuyAtLoss : buyerAssets ≤ boughtNetCredit) → (hIdle : buyerAssets ≤ s.idle) →
    sharePrice s ≤ sharePrice (buy s m buyerAssets boughtNetCredit)

/-- A self-funded buy doesn't decrease the share price. -/
def SharePriceSelfFundedBuy : Prop :=
  ∀ (s : State ι) (m fundingMarket : ι) (buyerAssets boughtNetCredit : ℕ),
    (hBuyAtLoss : buyerAssets ≤ boughtNetCredit) →
    (hWithdrawLessThanNetCredit : buyerAssets ≤ (recordBuy s m buyerAssets boughtNetCredit).netCredit fundingMarket) →
    sharePrice s ≤ sharePrice (selfFundedBuy s m fundingMarket buyerAssets boughtNetCredit)

/-- A sale in a market that isn't forceSellable doesn't decrease the share price. -/
def SharePriceSell [LinearOrder ι] : Prop :=
  ∀ (s : State ι) (m : ι) (sellerAssets soldNetCredit : ℕ),
    (hSellLessThanHeld : soldNetCredit ≤ s.netCredit m) →
    (hShortfallLessThanTotalInterest : let netCredit := Function.update s.netCredit m (s.netCredit m - soldNetCredit)
      shortfall s m sellerAssets soldNetCredit
        ≤ ∑ i, (netCredit i - amortizedValue (netCredit i) (s.netRate i) (s.ttm i))) →
    sharePrice s ≤ sharePrice (sell s m sellerAssets soldNetCredit)

/-- Withdrawing credit to the vault doesn't decrease the share price. -/
def SharePriceWithdraw : Prop :=
  ∀ (s : State ι) (m : ι) (assets : ℕ),
    (hWithdrawLessThanNetCredit : assets ≤ s.netCredit m) →
    sharePrice s ≤ sharePrice (withdraw s m assets)

/-- Force deallocation, including accrual and the penalty exit, doesn't decrease the share price.
Any extra liquidity withdrawal is assumed to preserve real assets as specified by `penaltyExit`. -/
def SharePriceForceDeallocate : Prop :=
  ∀ (s : State ι) (m : ι) (assets soldNetCredit penalty : ℕ),
    (hSellLessThanHeld : soldNetCredit ≤ s.netCredit m) → (hAssets : soldNetCredit ≤ assets) →
    (hVirtual : 0 < s.virtualShares) →
    (hPenalty : penalty ≤ newTotalAssets (recordForceDeallocate s m assets soldNetCredit)) →
    (hShares : previewWithdraw (recordForceDeallocate s m assets soldNetCredit) penalty
      ≤ s.totalSupply) →
    sharePrice s ≤ sharePrice (forceDeallocate s m assets soldNetCredit penalty)

end MidnightAdapterProofs
