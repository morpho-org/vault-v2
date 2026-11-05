import Mathlib

namespace MulDiv

theorem modular_polynomial (a b c m : Int) :
    (a * (b - c)) % m = ((a % m) * ((b - (c % m)) % m)) % m := by
  simp only [Int.mul_emod, Int.sub_emod, Int.emod_emod]

theorem divisible_products (a b m : Int) (ha : a % m = 0) (hb : b % m = 0) :
    (a * b) % (m * m) = 0 := by
  exact Int.emod_eq_zero_of_dvd
    (mul_dvd_mul (Int.dvd_of_emod_eq_zero ha) (Int.dvd_of_emod_eq_zero hb))

theorem cancel_modular_inverse (d q inv m : Int) (h : (d * inv) % m = 1) :
    (((d * q) % m) * inv) % m = q % m := by
  calc
    (((d * q) % m) * inv) % m = (d * q * inv) % m := by
      rw [Int.mul_emod, Int.emod_emod, ← Int.mul_emod]
    _ = (q * (d * inv)) % m := by congr 1; ring
    _ = ((q % m) * ((d * inv) % m)) % m := Int.mul_emod _ _ _
    _ = q % m := by rw [h]; simp

theorem shift_arithmetic {hi lo t u b : Nat} (ht : 0 < t)
    (he : b = u * t) (hlo : lo < b) :
    lo / t + (hi * (u % b)) % b = ((hi * b + lo) / t) % b := by
  have hl : lo / t < u := (Nat.div_lt_iff_lt_mul ht).2 (by rwa [← he])
  have hmul : (hi * (u % b)) % b = u * (hi % t) := by
    rw [Nat.mul_mod_mod, he, Nat.mul_comm hi u, Nat.mul_mod_mul_left]
  have hdiv : (hi * b + lo) / t = hi * u + lo / t := by
    rw [he, ← Nat.mul_assoc, Nat.mul_comm (hi * u) t, Nat.mul_add_div ht]
  rw [hmul, hdiv, Nat.add_mod, Nat.mul_comm hi u, he, Nat.mul_mod_mul_left,
    Nat.mod_eq_of_lt (show lo / t < u * t by
      rw [← he]; exact lt_of_le_of_lt (Nat.div_le_self _ _) hlo)]
  have hsum : u * (hi % t) + lo / t < u * t := by
    have := Nat.mod_lt hi ht
    nlinarith
  simpa [Nat.add_comm] using (Nat.mod_eq_of_lt hsum).symm

theorem word_shift_arithmetic {B hi lo t flipped : Nat} (hB : 0 < B) (hlo : lo < B)
    (ht : 0 < t) (hr : (B - 1) % t = t - 1)
    (hf : flipped = if t = 1 then 0 else (B - 1) / t + 1) :
    lo / t + (hi * flipped) % B = ((hi * B + lo) / t) % B := by
  let u := (B - 1) / t + 1
  have hu : 0 < u := by dsimp [u]; positivity
  have he : B = u * t := by
    have h := Nat.mod_add_div (B - 1) t
    rw [hr] at h
    dsimp [u]
    nlinarith [Nat.sub_add_cancel (show 1 ≤ t by omega),
      Nat.sub_add_cancel (show 1 ≤ B by omega)]
  have hflip : flipped = u % B := by
    by_cases h : t = 1
    · subst t
      have huB : u = B := by simpa using he.symm
      simpa [huB] using hf
    · have ht2 : 2 ≤ t := by omega
      have hut : u < B := by nlinarith
      rw [Nat.mod_eq_of_lt hut]
      simpa [h, u] using hf
  rw [hflip]
  exact shift_arithmetic ht he hlo

end MulDiv

#print axioms MulDiv.modular_polynomial
#print axioms MulDiv.divisible_products
#print axioms MulDiv.cancel_modular_inverse
#print axioms MulDiv.word_shift_arithmetic
