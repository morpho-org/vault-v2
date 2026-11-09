import Mathlib

namespace MidnightAdapterProofs

open Finset

def WAD : ℕ := 10 ^ 18

lemma WAD_pos : 0 < WAD := by unfold WAD; positivity

/-- `MathLib.mulDivDown`. -/
def mulDivDown (x y d : ℕ) : ℕ := x * y / d

/-- `MathLib.mulDivUp`. -/
def mulDivUp (x y d : ℕ) : ℕ := (x * y + (d - 1)) / d

/-- One term of `realAssets`: net credit `c` discounted at net rate `r` over `t` seconds to maturity. -/
def value (c r t : ℕ) : ℕ := mulDivDown c WAD (WAD + r * t)

/-- Rate set by `onBuy` and `onSell`: the rate that values net credit `c` at amortized value `a` over `t` seconds. -/
def rateFor (c a t : ℕ) : ℕ := mulDivDown (c - a) WAD (a * t)

lemma value_le_self (c r t : ℕ) : value c r t ≤ c := by
  unfold value mulDivDown
  calc c * WAD / (WAD + r * t) ≤ c * WAD / WAD := Nat.div_le_div_left (by omega) WAD_pos
    _ = c := Nat.mul_div_cancel c WAD_pos

lemma value_zero (r t : ℕ) : value 0 r t = 0 := by simp [value, mulDivDown]

/-- Key lemma: rounding the new rate down keeps the value at least the amortized value it targets. -/
lemma le_value_rateFor {c a : ℕ} (t : ℕ) (h : a ≤ c) : a ≤ value c (rateFor c a t) t := by
  unfold value rateFor mulDivDown
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
lemma value_sub_le {c s : ℕ} (r t : ℕ) (hs : s ≤ c) :
    value c r t ≤ value (c - s) r t + mulDivUp s WAD (WAD + r * t) := by
  unfold value mulDivDown mulDivUp
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

end MidnightAdapterProofs
