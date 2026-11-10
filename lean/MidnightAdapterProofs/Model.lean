import Mathlib

/-!
# Adapter operations don't decrease the vault's real assets

Model of a VaultV2 whose only adapter is a MidnightAdapter, with no bad debt in any market
(`lossFactor == 0`, so `realAssets` reads the stored net credit and Midnight's net credit moves only
by the traded amounts). Arithmetic is the contracts' unbounded-integer arithmetic with their exact
rounding; overflow and every other `require` failure make the call revert, so they need no modeling.

Time is fixed within a transaction, so each market has a fixed time to maturity `ttm`.
Adapter `allocate` is a no-op, setters and `skim` leave the modeled fields unchanged, and `take` routes through `onBuy` or `onSell`.
`skim` can transfer even the asset token from the adapter, but not the vault's idle balance, and adapter-held tokens are not counted by `realAssets`.
-/

/-!
# Adapter operations don't decrease the vault's share price

`VaultV2.accrueInterestView` with the MidnightAdapter as the only adapter, no performance fee and
no management fee. `_totalAssets`, `totalSupply` and `virtualShares` are left unchanged by
`allocate`/`deallocate` (the trade's own accrual runs on the pre-trade state, through
`inProgressBuy*` on buys), so the trade only changes `realAssets`. The theorems compare the vault's
share price after the trade with the share price without it, at the trade's timestamp: each market's
`ttm` is the one the trade used. Later accruals re-discount at a smaller `ttm`, and rate rounding can
then leave the traded state a few units of assets below the untraded one; that isn't covered.
Force deallocation additionally accrues and burns penalty shares, as modeled by `penaltyExit`.
-/

namespace MidnightAdapterProofs

open Finset

def WAD : ℕ := 10 ^ 18

/-- `MathLib.mulDivDown`. -/
def mulDivDown (x y d : ℕ) : ℕ := x * y / d

/-- `MathLib.mulDivUp`. -/
def mulDivUp (x y d : ℕ) : ℕ := (x * y + (d - 1)) / d

/-- One term of `realAssets`: net credit `c` discounted at net rate `r` over `t` seconds to maturity. -/
def amortizedValue (c r t : ℕ) : ℕ := mulDivDown c WAD (WAD + r * t)

/-- Rate set by `onBuy` and `onSell`: the rate that values net credit `c` at amortized value `a` over `t` seconds. -/
def netRate (c a t : ℕ) : ℕ := mulDivDown (c - a) WAD (a * t)

variable {ι : Type*} [Fintype ι] [DecidableEq ι]

/-- The vault's idle assets and the adapter's stored `marketData` (net credit, net rate,
time to maturity) for every market, indexed in `marketIds` order. Markets outside `marketIds` have zero net credit. -/
structure State (ι : Type*) where
  idle : ℕ
  netCredit : ι → ℕ
  netRate : ι → ℕ
  ttm : ι → ℕ

/-- `IERC20(asset).balanceOf(vault) + MidnightAdapter.realAssets()`. -/
def realAssets (s : State ι) : ℕ := s.idle + ∑ i, amortizedValue (s.netCredit i) (s.netRate i) (s.ttm i)

/-- `onBuy` outside forceDeallocate, adapter side: `boughtNetCredit` is added to the market's net
credit, and the market's rate is reset so that it is worth its pre-buy value plus `buyerAssets`. -/
def recordBuy (s : State ι) (m : ι) (buyerAssets boughtNetCredit : ℕ) : State ι :=
  let newNetCredit := s.netCredit m + boughtNetCredit
  let newAmortizedValue := amortizedValue (s.netCredit m) (s.netRate m) (s.ttm m) + buyerAssets
  { s with
    netCredit := Function.update s.netCredit m newNetCredit
    netRate := if 0 < newNetCredit then
        Function.update s.netRate m (netRate newNetCredit newAmortizedValue (s.ttm m))
      else s.netRate }

/-- A buy funded from the vault's idle assets (`fundingAdapter == address(0)`). -/
def buy (s : State ι) (m : ι) (buyerAssets boughtNetCredit : ℕ) : State ι :=
  { recordBuy s m buyerAssets boughtNetCredit with idle := s.idle - buyerAssets }

/-- `withdrawToVault`: Midnight withdraws `assets` of matured or repaid credit, which the vault pulls.
Used by `deallocate` and by self-funded buys. -/
def withdraw (s : State ι) (m : ι) (assets : ℕ) : State ι :=
  { s with
    idle := s.idle + assets
    netCredit := Function.update s.netCredit m (s.netCredit m - assets) }

/-- The adapter's `forceDeallocate` branch, including the vault pulling `assets`.
The sender funds `assets + settlementFee`, and no rate update or `onSell` runs.
In `lib/midnight/src/Midnight.sol:371-377,399-400`, seller credit decreases by at most the units passed to `take`, while pending-fee reduction offsets that loss.
The adapter passes `assets` as units at tick 0 in `src/adapters/MidnightAdapter.sol:398-425`.
With no bad debt, fee accrual subtracts the same amount from credit and pending fee (`Midnight.sol:805-816`), so the net-credit loss is at most `assets`.
The theorem retains this bound as `soldNetCredit ≤ assets`. -/
def forceDeallocate (s : State ι) (m : ι) (assets soldNetCredit : ℕ) : State ι :=
  { s with
    idle := s.idle + assets
    netCredit := Function.update s.netCredit m (s.netCredit m - soldNetCredit) }

/-- A self-funded buy (`fundingAdapter == address(this)`): `onBuy` records the buy, withdraws
`buyerAssets` from `fundingMarket` to the vault, and the vault then pays `buyerAssets`. -/
def selfFundedBuy (s : State ι) (m fundingMarket : ι) (buyerAssets boughtNetCredit : ℕ) : State ι :=
  let s₁ := withdraw (recordBuy s m buyerAssets boughtNetCredit) fundingMarket buyerAssets
  { s₁ with idle := s₁.idle - buyerAssets }

/-- Shortfall of a sale, as in `onSell`. -/
def shortfall (s : State ι) (m : ι) (sellerAssets soldNetCredit : ℕ) : ℕ :=
  mulDivUp soldNetCredit WAD (WAD + s.netRate m * s.ttm m) - sellerAssets

/-- `onSell` in a market that is not forceSellable: the vault receives `sellerAssets` for
`soldNetCredit`; if the sale has a shortfall, visited markets' rates are reduced so that their amortized
values grow by their shares (rounded up) of the shortfall, in proportion to their remaining interest.
Markets are visited in index order, stopping once the realized increase covers the shortfall. -/
def sell [LinearOrder ι] (s : State ι) (m : ι) (sellerAssets soldNetCredit : ℕ) : State ι :=
  let remainingNetCredit := Function.update s.netCredit m (s.netCredit m - soldNetCredit)
  let sf := shortfall s m sellerAssets soldNetCredit
  let amortizedValues := fun i => amortizedValue (remainingNetCredit i) (s.netRate i) (s.ttm i)
  let totalInterest := ∑ i, (remainingNetCredit i - amortizedValues i)
  let newRate := fun i =>
    if remainingNetCredit i = amortizedValues i then s.netRate i
    else netRate (remainingNetCredit i)
      (amortizedValues i + mulDivUp sf (remainingNetCredit i - amortizedValues i) totalInterest) (s.ttm i)
  let inc := fun i => amortizedValue (remainingNetCredit i) (newRate i) (s.ttm i) - amortizedValues i
  { idle := s.idle + sellerAssets
    netCredit := remainingNetCredit
    netRate := fun i =>
      if 0 < sf ∧ (∑ j ∈ Finset.univ.filter (· < i), inc j) < sf then newRate i else s.netRate i
    ttm := s.ttm }

/-- The vault's stored accounting: `_totalAssets`, `totalSupply`, `virtualShares`, `maxRate`, and
the time elapsed since `lastUpdate`. -/
structure Vault where
  totalAssets : ℕ
  totalSupply : ℕ
  virtualShares : ℕ
  maxRate : ℕ
  elapsed : ℕ

/-- `newTotalAssets` in `accrueInterestView`, for a vault whose real assets are `realAssets`. -/
def newTotalAssets (v : Vault) (realAssets : ℕ) : ℕ :=
  min realAssets (v.totalAssets + mulDivDown (v.totalAssets * v.elapsed) v.maxRate WAD)

/-- `previewRedeem` (and `convertToAssets`) without fees. -/
def previewRedeem (v : Vault) (realAssets shares : ℕ) : ℕ :=
  mulDivDown shares (newTotalAssets v realAssets + 1) (v.totalSupply + v.virtualShares)

/-- `previewDeposit` (and `convertToShares`) without fees. -/
def previewDeposit (v : Vault) (realAssets assets : ℕ) : ℕ :=
  mulDivDown assets (v.totalSupply + v.virtualShares) (newTotalAssets v realAssets + 1)

/-- `previewWithdraw` without fees (`src/VaultV2.sol:671-675`). -/
def previewWithdraw (v : Vault) (realAssets assets : ℕ) : ℕ :=
  mulDivUp assets (v.totalSupply + v.virtualShares) (newTotalAssets v realAssets + 1)

/-- Accrual followed by the penalty withdrawal to the vault itself (`src/VaultV2.sol:750-798`).
`realAssets` is the post-deallocation value and is unchanged by the self-transfer.
If `exit` needs liquidity, assume its extra deallocation preserves this value; this is exact for matured or fully repaid credit withdrawn at face value.
The theorems require sufficient total assets and supply for the checked subtractions, and positive virtual shares as set by the constructor. -/
def penaltyExit (v : Vault) (realAssets penalty : ℕ) : Vault :=
  { v with
    totalAssets := newTotalAssets v realAssets - penalty
    totalSupply := v.totalSupply - previewWithdraw v realAssets penalty
    elapsed := 0 }

end MidnightAdapterProofs
