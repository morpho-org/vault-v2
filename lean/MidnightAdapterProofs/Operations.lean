import MidnightAdapterProofs.Basic

/-!
# Buys and sells don't decrease the vault's real assets

Model of a VaultV2 whose only adapter is a MidnightAdapter, with no bad debt in any market
(`lossFactor == 0`, so `realAssets` reads the stored net credit and Midnight's net credit moves only
by the traded amounts). Arithmetic is the contracts' unbounded-integer arithmetic with their exact
rounding; overflow and every other `require` failure make the call revert, so they need no modeling.

Time is fixed within a transaction, so each market has a fixed time to maturity `ttm`.
-/

namespace MidnightAdapterProofs

open Finset

variable {ι : Type*} [Fintype ι] [DecidableEq ι]

/-- The vault's idle assets and the adapter's stored `marketData` (net credit, net rate,
time to maturity) for every market. Markets outside `marketIds` have zero net credit. -/
structure State (ι : Type*) where
  idle : ℕ
  credit : ι → ℕ
  rate : ι → ℕ
  ttm : ι → ℕ

/-- `IERC20(asset).balanceOf(vault) + MidnightAdapter.realAssets()`. -/
def realAssets (s : State ι) : ℕ := s.idle + ∑ i, amortizedValue (s.credit i) (s.rate i) (s.ttm i)

/-- `onBuy` outside forceDeallocate, adapter side: `boughtNetCredit` is added to the market's net
credit, and the market's rate is reset so that it is worth its pre-buy value plus `buyerAssets`. -/
def recordBuy (s : State ι) (m : ι) (buyerAssets boughtNetCredit : ℕ) : State ι :=
  let newNetCredit := s.credit m + boughtNetCredit
  let newAmortizedValue := amortizedValue (s.credit m) (s.rate m) (s.ttm m) + buyerAssets
  { s with
    credit := Function.update s.credit m newNetCredit
    rate := if 0 < newNetCredit then
        Function.update s.rate m (netRate newNetCredit newAmortizedValue (s.ttm m))
      else s.rate }

/-- A buy funded from the vault's idle assets (`fundingAdapter == address(0)`). -/
def buy (s : State ι) (m : ι) (buyerAssets boughtNetCredit : ℕ) : State ι :=
  { recordBuy s m buyerAssets boughtNetCredit with idle := s.idle - buyerAssets }

/-- `withdrawToVault`: Midnight withdraws `assets` of matured or repaid credit, which the vault pulls.
Used by `deallocate` and by self-funded buys. -/
def withdraw (s : State ι) (m : ι) (assets : ℕ) : State ι :=
  { s with
    idle := s.idle + assets
    credit := Function.update s.credit m (s.credit m - assets) }

/-- A self-funded buy (`fundingAdapter == address(this)`): `onBuy` records the buy, withdraws
`buyerAssets` from `fundingMarket` to the vault, and the vault then pays `buyerAssets`. -/
def selfFundedBuy (s : State ι) (m fundingMarket : ι) (buyerAssets boughtNetCredit : ℕ) : State ι :=
  let s₁ := withdraw (recordBuy s m buyerAssets boughtNetCredit) fundingMarket buyerAssets
  { s₁ with idle := s₁.idle - buyerAssets }

/-- Shortfall of a sale, as in `onSell`. -/
def shortfall (s : State ι) (m : ι) (sellerAssets soldNetCredit : ℕ) : ℕ :=
  mulDivUp soldNetCredit WAD (WAD + s.rate m * s.ttm m) - sellerAssets

/-- `onSell` in a market that is not forceSellable: the vault receives `sellerAssets` for
`soldNetCredit`; if the sale has a shortfall, every market's rate is reduced so that its amortized
value grows by its share (rounded up) of the shortfall, in proportion to its remaining interest. -/
def sell (s : State ι) (m : ι) (sellerAssets soldNetCredit : ℕ) : State ι :=
  let netCredit := Function.update s.credit m (s.credit m - soldNetCredit)
  let sf := shortfall s m sellerAssets soldNetCredit
  let amortizedValues := fun i => amortizedValue (netCredit i) (s.rate i) (s.ttm i)
  let totalInterest := ∑ i, (netCredit i - amortizedValues i)
  let newRate := fun i =>
    if netCredit i = amortizedValues i then s.rate i
    else netRate (netCredit i)
      (amortizedValues i + mulDivUp sf (netCredit i - amortizedValues i) totalInterest) (s.ttm i)
  { idle := s.idle + sellerAssets
    credit := netCredit
    rate := if 0 < sf then newRate else s.rate
    ttm := s.ttm }

/-! ## Theorems -/

omit [Fintype ι] in
@[simp] lemma recordBuy_idle (s : State ι) (m : ι) (a b : ℕ) : (recordBuy s m a b).idle = s.idle := rfl
omit [Fintype ι] in
@[simp] lemma recordBuy_ttm (s : State ι) (m : ι) (a b : ℕ) : (recordBuy s m a b).ttm = s.ttm := rfl
omit [Fintype ι] in
@[simp] lemma withdraw_idle (s : State ι) (m : ι) (a : ℕ) : (withdraw s m a).idle = s.idle + a := rfl

/-- Recording a buy increases the adapter's value by at least `buyerAssets`. -/
theorem realAssets_recordBuy (s : State ι) (m : ι) (buyerAssets boughtNetCredit : ℕ)
    (hBuyAtLoss : buyerAssets ≤ boughtNetCredit) :
    realAssets s + buyerAssets ≤ realAssets (recordBuy s m buyerAssets boughtNetCredit) := by
  unfold realAssets recordBuy
  simp only
  rw [add_assoc]
  apply Nat.add_le_add_left
  apply sum_add_le_sum m
  · intro i hi
    split_ifs <;> simp [Function.update_of_ne hi]
  · by_cases h : 0 < s.credit m + boughtNetCredit
    · simp only [h, ite_true, Function.update_self]
      apply le_amortizedValue_netRate
      have := amortizedValue_le_self (s.credit m) (s.rate m) (s.ttm m)
      omega
    · have h1 : s.credit m = 0 := by omega
      have h2 : buyerAssets = 0 := by omega
      have h3 : boughtNetCredit = 0 := by omega
      simp [h1, h2, h3, amortizedValue_zero]

theorem realAssets_buy (s : State ι) (m : ι) (buyerAssets boughtNetCredit : ℕ)
    (hBuyAtLoss : buyerAssets ≤ boughtNetCredit) (hIdle : buyerAssets ≤ s.idle) :
    realAssets s ≤ realAssets (buy s m buyerAssets boughtNetCredit) := by
  have := realAssets_recordBuy s m buyerAssets boughtNetCredit hBuyAtLoss
  unfold realAssets buy at *
  simp only [recordBuy_idle] at *
  omega

theorem realAssets_withdraw (s : State ι) (m : ι) (assets : ℕ) (h : assets ≤ s.credit m) :
    realAssets s ≤ realAssets (withdraw s m assets) := by
  unfold realAssets withdraw
  have := sum_le_sum_add (f := fun i => amortizedValue (s.credit i) (s.rate i) (s.ttm i))
    (g := fun i => amortizedValue (Function.update s.credit m (s.credit m - assets) i) (s.rate i) (s.ttm i))
    m assets (by intro i hi; simp [Function.update_of_ne hi])
    (by
      simp only [Function.update_self]
      have := amortizedValue_sub_le (s.rate m) (s.ttm m) h
      have := mulDivUp_le_self assets (s.rate m) (s.ttm m)
      omega)
  dsimp only
  omega

theorem realAssets_selfFundedBuy (s : State ι) (m fundingMarket : ι) (buyerAssets boughtNetCredit : ℕ)
    (hBuyAtLoss : buyerAssets ≤ boughtNetCredit)
    (hWithdrawable : buyerAssets ≤ (recordBuy s m buyerAssets boughtNetCredit).credit fundingMarket) :
    realAssets s ≤ realAssets (selfFundedBuy s m fundingMarket buyerAssets boughtNetCredit) := by
  have h1 := realAssets_recordBuy s m buyerAssets boughtNetCredit hBuyAtLoss
  have h2 := realAssets_withdraw _ fundingMarket buyerAssets hWithdrawable
  unfold realAssets selfFundedBuy at *
  simp only [withdraw_idle, recordBuy_idle] at *
  unfold withdraw at *
  omega

/-- A sale outside forceSellable markets doesn't decrease the vault's real assets. `hShortfall` is
`onSell`'s `require(shortfall <= totalInterest, ShortfallTooHigh())`. -/
theorem realAssets_sell (s : State ι) (m : ι) (sellerAssets soldNetCredit : ℕ)
    (hSold : soldNetCredit ≤ s.credit m)
    (hShortfall : let netCredit := Function.update s.credit m (s.credit m - soldNetCredit)
      shortfall s m sellerAssets soldNetCredit
        ≤ ∑ i, (netCredit i - amortizedValue (netCredit i) (s.rate i) (s.ttm i))) :
    realAssets s ≤ realAssets (sell s m sellerAssets soldNetCredit) := by
  set c' := Function.update s.credit m (s.credit m - soldNetCredit) with hc'
  set sf := shortfall s m sellerAssets soldNetCredit with hsf
  set v := fun i => amortizedValue (c' i) (s.rate i) (s.ttm i) with hv
  set I := ∑ i, (c' i - v i) with hI
  -- Selling at old rates: the vault's real assets drop by at most the shortfall.
  have hOld : ∑ i, amortizedValue (s.credit i) (s.rate i) (s.ttm i) ≤ ∑ i, v i + (sellerAssets + sf) := by
    apply sum_le_sum_add m
    · intro i hi; simp [hv, hc', Function.update_of_ne hi]
    · simp only [hv, hc', Function.update_self]
      have := amortizedValue_sub_le (s.rate m) (s.ttm m) hSold
      have : mulDivUp soldNetCredit WAD (WAD + s.rate m * s.ttm m) ≤ sellerAssets + sf := by
        simp only [hsf, shortfall]; omega
      omega
  unfold realAssets sell
  simp only [← hc', ← hsf]
  by_cases hpos : 0 < sf
  · simp only [hpos, ite_true]
    have hSI : sf ≤ I := hShortfall
    have hIpos : 0 < I := lt_of_lt_of_le hpos hSI
    set x := fun i => mulDivUp sf (c' i - v i) I with hx
    -- Each market gains at least its share of the shortfall.
    have hEach : ∀ i, v i + x i ≤ amortizedValue (c' i)
        (if c' i = amortizedValue (c' i) (s.rate i) (s.ttm i) then s.rate i
          else netRate (c' i) (amortizedValue (c' i) (s.rate i) (s.ttm i)
            + mulDivUp sf (c' i - amortizedValue (c' i) (s.rate i) (s.ttm i)) I) (s.ttm i)) (s.ttm i) := by
      intro i
      by_cases heq : c' i = amortizedValue (c' i) (s.rate i) (s.ttm i)
      · rw [ite_cond_eq_true _ _ (eq_true heq)]
        have h0 : c' i - v i = 0 := by show c' i - amortizedValue (c' i) (s.rate i) (s.ttm i) = 0; omega
        have : x i = 0 := by show mulDivUp sf (c' i - v i) I = 0; rw [h0]; exact mulDivUp_zero_left _ _ hIpos
        rw [this]; exact Nat.le_refl _
      · rw [ite_cond_eq_false _ _ (eq_false heq)]
        apply le_amortizedValue_netRate
        have h1 : x i ≤ c' i - v i := mulDivUp_le_of_le hIpos hSI
        have h2 : v i ≤ c' i := amortizedValue_le_self (c' i) (s.rate i) (s.ttm i)
        omega
    -- The shares sum to at least the shortfall.
    have hShares : sf ≤ ∑ i, x i := by
      have : sf * I ≤ (∑ i, x i) * I :=
        calc sf * I = ∑ i, sf * (c' i - v i) := by rw [hI, Finset.mul_sum]
          _ ≤ ∑ i, x i * I := sum_le_sum (fun i _ => le_mulDivUp_mul sf (c' i - v i) I hIpos)
          _ = (∑ i, x i) * I := by rw [Finset.sum_mul]
      exact Nat.le_of_mul_le_mul_right this hIpos
    have hNew := sum_le_sum (s := Finset.univ) (fun i _ => hEach i)
    rw [sum_add_distrib] at hNew
    calc s.idle + ∑ i, amortizedValue (s.credit i) (s.rate i) (s.ttm i)
        ≤ s.idle + sellerAssets + (∑ i, v i + ∑ i, x i) := by omega
      _ ≤ _ := Nat.add_le_add_left hNew _
  · simp only [hpos, ite_false]
    have : sf = 0 := by omega
    have : ∑ i, v i = ∑ i, amortizedValue (c' i) (s.rate i) (s.ttm i) := rfl
    omega

end MidnightAdapterProofs
