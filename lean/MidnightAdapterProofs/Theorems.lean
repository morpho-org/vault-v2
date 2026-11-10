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
  ∀ (s : State ι) (m : ι) (buyerAssets boughtNetCredit : ℕ) (s' : State ι),
    buy s m buyerAssets boughtNetCredit = some s' →
    sharePrice s ≤ sharePrice s'

/-- A self-funded buy doesn't decrease the share price. -/
def SharePriceSelfFundedBuy : Prop :=
  ∀ (s : State ι) (m fundingMarket : ι) (buyerAssets boughtNetCredit : ℕ) (s' : State ι),
    selfFundedBuy s m fundingMarket buyerAssets boughtNetCredit = some s' →
    sharePrice s ≤ sharePrice s'

/-- A sale in a market that isn't forceSellable doesn't decrease the share price. -/
def SharePriceSell [LinearOrder ι] : Prop :=
  ∀ (s : State ι) (m : ι) (sellerAssets soldNetCredit : ℕ) (s' : State ι),
    sell s m sellerAssets soldNetCredit = some s' →
    sharePrice s ≤ sharePrice s'

/-- Withdrawing credit to the vault doesn't decrease the share price. -/
def SharePriceWithdraw : Prop :=
  ∀ (s : State ι) (m : ι) (assets : ℕ) (s' : State ι),
    withdraw s m assets = some s' →
    sharePrice s ≤ sharePrice s'

/-- Force deallocation, including accrual and the penalty exit, doesn't decrease the share price.
Any extra liquidity withdrawal is assumed to preserve real assets as specified by `penaltyExit`. -/
def SharePriceForceDeallocate : Prop :=
  ∀ (s : State ι) (m : ι) (assets soldNetCredit penalty : ℕ) (s' : State ι),
    forceDeallocate s m assets soldNetCredit penalty = some s' →
    (hSoldLessThanAssets : soldNetCredit ≤ assets) →
    (hPositiveVirtualShares : 0 < s.virtualShares) →
    sharePrice s ≤ sharePrice s'

end MidnightAdapterProofs
