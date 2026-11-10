import MidnightAdapterProofs.Model

namespace MidnightAdapterProofs

open Finset

lemma WAD_pos : 0 < WAD := by unfold WAD; positivity

lemma amortizedValue_le_self (c r t : ℕ) : amortizedValue c r t ≤ c := by
  unfold amortizedValue mulDivDown
  calc c * WAD / (WAD + r * t) ≤ c * WAD / WAD := Nat.div_le_div_left (by omega) WAD_pos
    _ = c := Nat.mul_div_cancel c WAD_pos

lemma amortizedValue_zero (r t : ℕ) : amortizedValue 0 r t = 0 := by simp [amortizedValue, mulDivDown]

/-- Key lemma: rounding the new rate down keeps the value at least the amortized value it targets. -/
lemma le_amortizedValue_netRate {c a : ℕ} (t : ℕ) (h : a ≤ c) : a ≤ amortizedValue c (netRate c a t) t := by
  unfold amortizedValue netRate mulDivDown
  rw [Nat.le_div_iff_mul_le (by have := WAD_pos; positivity)]
  have h1 : (c - a) * WAD / (a * t) * (a * t) ≤ (c - a) * WAD := Nat.div_mul_le_self _ _
  have h2 : (c - a) * WAD + a * WAD = c * WAD := by rw [← Nat.add_mul, Nat.sub_add_cancel h]
  nlinarith

lemma mulDivUp_le_self (s r t : ℕ) : mulDivUp s WAD (WAD + r * t) ≤ s := by
  unfold mulDivUp
  have hD : 0 < WAD + r * t := by have := WAD_pos; omega
  have : s * WAD ≤ s * (WAD + r * t) := Nat.mul_le_mul_left _ (by omega)
  have := Nat.div_lt_iff_lt_mul hD |>.mpr (show s * WAD + (WAD + r * t - 1) < (s + 1) * (WAD + r * t) by
    rw [Nat.add_mul]; omega)
  omega

/-- `(A + B) / D ≤ A / D + ⌈B / D⌉`. -/
lemma add_div_le (A B D : ℕ) (hD : 0 < D) : (A + B) / D ≤ A / D + (B + (D - 1)) / D := by
  have hA := Nat.div_add_mod A D
  have hr := Nat.mod_lt A hD
  have : A + B = (B + A % D) + D * (A / D) := by omega
  rw [this, Nat.add_mul_div_left _ _ hD, add_comm (A / D)]
  exact Nat.add_le_add_right (Nat.div_le_div_right (by omega)) _

/-- Decreasing net credit by `s` decreases the value by at most `s` discounted and rounded up. -/
lemma amortizedValue_sub_le {c s : ℕ} (r t : ℕ) (hs : s ≤ c) :
    amortizedValue c r t ≤ amortizedValue (c - s) r t + mulDivUp s WAD (WAD + r * t) := by
  unfold amortizedValue mulDivDown mulDivUp
  have : c * WAD = (c - s) * WAD + s * WAD := by rw [← Nat.add_mul, Nat.sub_add_cancel hs]
  rw [this]
  exact add_div_le _ _ _ (by have := WAD_pos; omega)

lemma le_mulDivUp_mul (x y d : ℕ) (hd : 0 < d) : x * y ≤ mulDivUp x y d * d := by
  unfold mulDivUp
  have := Nat.lt_div_mul_add (a := x * y + (d - 1)) hd
  omega

lemma mulDivUp_le_of_le {sf i I : ℕ} (hI : 0 < I) (h : sf ≤ I) : mulDivUp sf i I ≤ i := by
  unfold mulDivUp
  have : sf * i ≤ I * i := Nat.mul_le_mul_right _ h
  have := Nat.div_lt_iff_lt_mul hI |>.mpr (show sf * i + (I - 1) < (i + 1) * I by
    rw [Nat.add_mul, Nat.mul_comm i I]; omega)
  omega

lemma mulDivUp_zero_left (y d : ℕ) (hd : 0 < d) : mulDivUp y 0 d = 0 := by
  unfold mulDivUp; simp; omega

/-! ## Sums -/

variable {ι : Type*} [Fintype ι] [DecidableEq ι]

lemma sum_le_sum_add {f g : ι → ℕ} (m : ι) (d : ℕ) (h : ∀ i, i ≠ m → f i ≤ g i)
    (hm : f m ≤ g m + d) : ∑ i, f i ≤ ∑ i, g i + d := by
  calc ∑ i, f i ≤ ∑ i, (g i + if i = m then d else 0) := by
        apply sum_le_sum; intro i _
        by_cases hi : i = m
        · subst hi; simpa using hm
        · simpa [hi] using h i hi
    _ = ∑ i, g i + d := by rw [sum_add_distrib, sum_ite_eq']; simp

lemma sum_add_le_sum {f g : ι → ℕ} (m : ι) (d : ℕ) (h : ∀ i, i ≠ m → f i ≤ g i)
    (hm : f m + d ≤ g m) : ∑ i, f i + d ≤ ∑ i, g i := by
  calc ∑ i, f i + d = ∑ i, (f i + if i = m then d else 0) := by
        rw [sum_add_distrib, sum_ite_eq']; simp
    _ ≤ ∑ i, g i := by
        apply sum_le_sum; intro i _
        by_cases hi : i = m
        · subst hi; simpa using hm
        · simpa [hi] using h i hi

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
  · by_cases h : 0 < s.netCredit m + boughtNetCredit
    · simp only [h, ite_true, Function.update_self]
      apply le_amortizedValue_netRate
      have := amortizedValue_le_self (s.netCredit m) (s.netRate m) (s.ttm m)
      omega
    · have h1 : s.netCredit m = 0 := by omega
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

theorem realAssets_withdraw (s : State ι) (m : ι) (assets : ℕ) (h : assets ≤ s.netCredit m) :
    realAssets s ≤ realAssets (withdraw s m assets) := by
  unfold realAssets withdraw
  have := sum_le_sum_add (f := fun i => amortizedValue (s.netCredit i) (s.netRate i) (s.ttm i))
    (g := fun i => amortizedValue (Function.update s.netCredit m (s.netCredit m - assets) i) (s.netRate i) (s.ttm i))
    m assets (by intro i hi; simp [Function.update_of_ne hi])
    (by
      simp only [Function.update_self]
      have := amortizedValue_sub_le (s.netRate m) (s.ttm m) h
      have := mulDivUp_le_self assets (s.netRate m) (s.ttm m)
      omega)
  dsimp only
  omega

theorem realAssets_forceDeallocate (s : State ι) (m : ι) (assets soldNetCredit : ℕ)
    (hSold : soldNetCredit ≤ s.netCredit m) (hAssets : soldNetCredit ≤ assets) :
    realAssets s ≤ realAssets (forceDeallocate s m assets soldNetCredit) := by
  have h := realAssets_withdraw s m soldNetCredit hSold
  unfold realAssets withdraw forceDeallocate at *
  dsimp only at *
  omega

theorem realAssets_selfFundedBuy (s : State ι) (m fundingMarket : ι) (buyerAssets boughtNetCredit : ℕ)
    (hBuyAtLoss : buyerAssets ≤ boughtNetCredit)
    (hWithdrawable : buyerAssets ≤ (recordBuy s m buyerAssets boughtNetCredit).netCredit fundingMarket) :
    realAssets s ≤ realAssets (selfFundedBuy s m fundingMarket buyerAssets boughtNetCredit) := by
  have h1 := realAssets_recordBuy s m buyerAssets boughtNetCredit hBuyAtLoss
  have h2 := realAssets_withdraw _ fundingMarket buyerAssets hWithdrawable
  unfold realAssets selfFundedBuy at *
  simp only [withdraw_idle, recordBuy_idle] at *
  unfold withdraw at *
  omega

variable [LinearOrder ι]

omit [DecidableEq ι] in
lemma sum_cutoff_ge (inc : ι → ℕ) (sf : ℕ) (h : sf ≤ ∑ i, inc i) :
    sf ≤ ∑ i, if (∑ j ∈ univ.filter (· < i), inc j) < sf then inc i else 0 := by
  classical
  let stopped := univ.filter (fun i => sf ≤ ∑ j ∈ univ.filter (· < i), inc j)
  by_cases hs : stopped.Nonempty
  · let k := stopped.min' hs
    have hk : k ∈ stopped := min'_mem stopped hs
    have hsf : sf ≤ ∑ j ∈ univ.filter (· < k), inc j := (mem_filter.mp hk).2
    calc
      sf ≤ ∑ j ∈ univ.filter (· < k), inc j := hsf
      _ = ∑ j ∈ univ.filter (· < k),
          if (∑ l ∈ univ.filter (· < j), inc l) < sf then inc j else 0 := by
        apply sum_congr rfl
        intro j hj
        have hjk : j < k := (mem_filter.mp hj).2
        have hlt : (∑ l ∈ univ.filter (· < j), inc l) < sf := by
          by_contra hn
          have hjmem : j ∈ stopped := mem_filter.mpr ⟨mem_univ _, by omega⟩
          have := min'_le stopped j hjmem
          exact (not_le_of_gt hjk) this
        simp [hlt]
      _ ≤ ∑ j, if (∑ l ∈ univ.filter (· < j), inc l) < sf then inc j else 0 :=
        sum_le_sum_of_subset (filter_subset _ _)
  · have hlt : ∀ i, (∑ j ∈ univ.filter (· < i), inc j) < sf := by
      intro i
      by_contra hn
      exact hs ⟨i, mem_filter.mpr ⟨mem_univ _, by omega⟩⟩
    simpa only [ite_eq_left (hlt _)] using h

/-- A sale outside forceSellable markets doesn't decrease the vault's real assets. `hShortfall` is
`onSell`'s `require(shortfall <= totalInterest, ShortfallTooHigh())`. -/
theorem realAssets_sell (s : State ι) (m : ι) (sellerAssets soldNetCredit : ℕ)
    (hSold : soldNetCredit ≤ s.netCredit m)
    (hShortfall : let netCredit := Function.update s.netCredit m (s.netCredit m - soldNetCredit)
      shortfall s m sellerAssets soldNetCredit
        ≤ ∑ i, (netCredit i - amortizedValue (netCredit i) (s.netRate i) (s.ttm i))) :
    realAssets s ≤ realAssets (sell s m sellerAssets soldNetCredit) := by
  set c' := Function.update s.netCredit m (s.netCredit m - soldNetCredit) with hc'
  set sf := shortfall s m sellerAssets soldNetCredit with hsf
  set v := fun i => amortizedValue (c' i) (s.netRate i) (s.ttm i) with hv
  set I := ∑ i, (c' i - v i) with hI
  -- Selling at old rates: the vault's real assets drop by at most the shortfall.
  have hOld : ∑ i, amortizedValue (s.netCredit i) (s.netRate i) (s.ttm i) ≤ ∑ i, v i + (sellerAssets + sf) := by
    apply sum_le_sum_add m
    · intro i hi; simp [hv, hc', Function.update_of_ne hi]
    · simp only [hv, hc', Function.update_self]
      have := amortizedValue_sub_le (s.netRate m) (s.ttm m) hSold
      have : mulDivUp soldNetCredit WAD (WAD + s.netRate m * s.ttm m) ≤ sellerAssets + sf := by
        simp only [hsf, shortfall]; omega
      omega
  by_cases hpos : 0 < sf
  · have hSI : sf ≤ I := hShortfall
    have hIpos : 0 < I := lt_of_lt_of_le hpos hSI
    set x := fun i => mulDivUp sf (c' i - v i) I with hx
    -- Each market gains at least its share of the shortfall.
    have hEach : ∀ i, v i + x i ≤ amortizedValue (c' i)
        (if c' i = amortizedValue (c' i) (s.netRate i) (s.ttm i) then s.netRate i
          else netRate (c' i) (amortizedValue (c' i) (s.netRate i) (s.ttm i)
            + mulDivUp sf (c' i - amortizedValue (c' i) (s.netRate i) (s.ttm i)) I) (s.ttm i)) (s.ttm i) := by
      intro i
      by_cases heq : c' i = amortizedValue (c' i) (s.netRate i) (s.ttm i)
      · rw [ite_cond_eq_true _ _ (eq_true heq)]
        have h0 : c' i - v i = 0 := by show c' i - amortizedValue (c' i) (s.netRate i) (s.ttm i) = 0; omega
        have : x i = 0 := by show mulDivUp sf (c' i - v i) I = 0; rw [h0]; exact mulDivUp_zero_left _ _ hIpos
        rw [this]; exact Nat.le_refl _
      · rw [ite_cond_eq_false _ _ (eq_false heq)]
        apply le_amortizedValue_netRate
        have h1 : x i ≤ c' i - v i := mulDivUp_le_of_le hIpos hSI
        have h2 : v i ≤ c' i := amortizedValue_le_self (c' i) (s.netRate i) (s.ttm i)
        omega
    -- The shares sum to at least the shortfall.
    have hShares : sf ≤ ∑ i, x i := by
      have : sf * I ≤ (∑ i, x i) * I :=
        calc sf * I = ∑ i, sf * (c' i - v i) := by rw [hI, Finset.mul_sum]
          _ ≤ ∑ i, x i * I := sum_le_sum (fun i _ => le_mulDivUp_mul sf (c' i - v i) I hIpos)
          _ = (∑ i, x i) * I := by rw [Finset.sum_mul]
      exact Nat.le_of_mul_le_mul_right this hIpos
    let target := fun i =>
      if c' i = amortizedValue (c' i) (s.netRate i) (s.ttm i) then s.netRate i
      else netRate (c' i) (amortizedValue (c' i) (s.netRate i) (s.ttm i)
        + mulDivUp sf (c' i - amortizedValue (c' i) (s.netRate i) (s.ttm i)) I) (s.ttm i)
    let inc := fun i => amortizedValue (c' i) (target i) (s.ttm i) - v i
    have hInc : ∀ i, x i ≤ inc i := by
      intro i
      have := hEach i
      change v i + x i ≤ amortizedValue (c' i) (target i) (s.ttm i) at this
      dsimp [inc]
      omega
    have hFull : sf ≤ ∑ i, inc i :=
      le_trans hShares (sum_le_sum (fun i _ => hInc i))
    have hCut := sum_cutoff_ge inc sf hFull
    have hNew : (∑ i, v i) +
        (∑ i, if (∑ j ∈ univ.filter (· < i), inc j) < sf then inc i else 0)
        ≤ ∑ i, amortizedValue (c' i)
          (if (∑ j ∈ univ.filter (· < i), inc j) < sf then target i else s.netRate i)
          (s.ttm i) := by
      rw [← sum_add_distrib]
      apply sum_le_sum
      intro i _
      split_ifs with hi
      · have := hEach i
        change v i + x i ≤ amortizedValue (c' i) (target i) (s.ttm i) at this
        dsimp [inc]
        omega
      · simp only [add_zero]
        exact le_refl _
    unfold realAssets sell
    simp only [← hc', ← hsf, hpos, true_and]
    change s.idle + ∑ i, amortizedValue (s.netCredit i) (s.netRate i) (s.ttm i) ≤
      s.idle + sellerAssets + ∑ i, amortizedValue (c' i)
        (if (∑ j ∈ univ.filter (· < i), inc j) < sf then target i else s.netRate i)
        (s.ttm i)
    omega
  · have : sf = 0 := by omega
    unfold realAssets sell
    simp only [← hc', ← hsf, hpos, false_and, ite_false]
    have : ∑ i, v i = ∑ i, amortizedValue (c' i) (s.netRate i) (s.ttm i) := rfl
    omega

lemma sharePrice_mono (v : Vault) {r r' : ℕ} (h : r ≤ r') :
    sharePrice v r ≤ sharePrice v r' := by
  unfold sharePrice
  apply div_le_div_of_nonneg_right _ (by positivity)
  have : newTotalAssets v r ≤ newTotalAssets v r' := by unfold newTotalAssets; omega
  exact_mod_cast Nat.add_le_add_right this 1

lemma newTotalAssets_penaltyExit (v : Vault) (r p : ℕ) :
    newTotalAssets (penaltyExit v r p) r = newTotalAssets v r - p := by
  have h : newTotalAssets v r ≤ r := min_le_left _ _
  simp only [newTotalAssets, penaltyExit, mulDivDown, Nat.mul_zero, Nat.zero_mul,
    Nat.zero_div, Nat.add_zero]
  change min r (newTotalAssets v r - p) = newTotalAssets v r - p
  omega

lemma penaltyExit_ratio (v : Vault) (r p : ℕ)
    (hPenalty : p ≤ newTotalAssets v r)
    (hShares : previewWithdraw v r p ≤ v.totalSupply) :
    (newTotalAssets v r + 1) * ((penaltyExit v r p).totalSupply + v.virtualShares) ≤
      (newTotalAssets v r - p + 1) * (v.totalSupply + v.virtualShares) := by
  have hround := le_mulDivUp_mul p (v.totalSupply + v.virtualShares)
    (newTotalAssets v r + 1) (by omega)
  change p * (v.totalSupply + v.virtualShares) ≤
    previewWithdraw v r p * (newTotalAssets v r + 1) at hround
  have hp := Nat.sub_add_cancel hPenalty
  have hs := Nat.sub_add_cancel hShares
  dsimp only [penaltyExit]
  nlinarith

lemma sharePrice_penaltyExit (v : Vault) (r p : ℕ)
    (hVirtual : 0 < v.virtualShares) (hPenalty : p ≤ newTotalAssets v r)
    (hShares : previewWithdraw v r p ≤ v.totalSupply) :
    sharePrice v r ≤ sharePrice (penaltyExit v r p) r := by
  unfold sharePrice
  rw [newTotalAssets_penaltyExit]
  apply (div_le_div_iff₀ (by positivity) (by dsimp only [penaltyExit]; positivity)).mpr
  exact_mod_cast penaltyExit_ratio v r p hPenalty hShares

end MidnightAdapterProofs
