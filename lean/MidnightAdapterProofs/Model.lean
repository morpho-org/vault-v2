import Mathlib

/-!
# Adapter operations don't decrease the vault's real assets

Model of a VaultV2 whose only adapter is a MidnightAdapter, with no bad debt in any market (`lossFactor == 0`, so `realAssets` reads the stored net credit and Midnight's net credit moves only by the traded amounts).
Arithmetic uses unbounded integers with the contracts' exact rounding.
Public modeled operations return `none` for the encoded reverting conditions and `some` for successful state transitions.
The theorems cover every non-reverting modeled call, subject to the stated scope and accounting assumptions.
Other authorization, configuration, token, liquidity and overflow checks are outside this state abstraction.
The `*State` helpers describe only successful arithmetic transitions.

Time is fixed within a transaction, so each market has a fixed time to maturity `ttm`.
Adapter `allocate` is a no-op, setters and `skim` leave the modeled fields unchanged, and `take` routes through `onBuy` or `onSell`.
`skim` can transfer even the asset token from the adapter, but not the vault's idle balance, and adapter-held tokens are not counted by `realAssets`.
-/

/-!
# Adapter operations don't decrease the vault's share price

`VaultV2.accrueInterestView` is modeled with no performance or management fee and no prior transaction-local `firstTotalAssets` cache.
Buys accrue against the pre-buy valuation exposed by `inProgressBuy*`, while force deallocation accrues after the adapter sale.
Sales and ordinary adapter withdrawals leave the vault accounting unchanged.
The theorems compare share prices at the operation's timestamp, with each market's `ttm` fixed.
Later accruals re-discount at a smaller `ttm`, and rate rounding can then leave the traded state a few units of assets below the untraded one; that isn't covered.
Force deallocation additionally accrues and burns penalty shares within the same state.
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

/-- The vault and its MidnightAdapter, with markets indexed in `marketIds` order.
Markets outside `marketIds` have zero net credit. -/
structure State (ι : Type*) where
  /-- The vault's idle balance, `IERC20(asset).balanceOf(vault)`. -/
  idle : ℕ
  /-- The adapter's `marketData[id].netCredit`. -/
  netCredit : ι → ℕ
  /-- The adapter's `marketData[id].netRate`. -/
  netRate : ι → ℕ
  /-- The adapter's `marketData[id].maturity.zeroFloorSub(block.timestamp)`. -/
  ttm : ι → ℕ
  /-- The vault's `_totalAssets`. -/
  totalAssets : ℕ
  /-- The vault's `totalSupply`. -/
  totalSupply : ℕ
  /-- The vault's `virtualShares`. -/
  virtualShares : ℕ
  /-- The vault's `maxRate`. -/
  maxRate : ℕ
  /-- `block.timestamp - lastUpdate` in the vault. -/
  elapsed : ℕ

/-- `IERC20(asset).balanceOf(vault) + MidnightAdapter.realAssets()`. -/
def realAssets (s : State ι) : ℕ := s.idle + ∑ i, amortizedValue (s.netCredit i) (s.netRate i) (s.ttm i)

/-- `newTotalAssets` in the vault's `accrueInterestView`. -/
def newTotalAssets (s : State ι) : ℕ :=
  min (realAssets s) (s.totalAssets + mulDivDown (s.totalAssets * s.elapsed) s.maxRate WAD)

/-- `onBuy` outside forceDeallocate, adapter side: `boughtNetCredit` is added to the market's net credit, and the market's rate is reset so that it is worth its pre-buy value plus `buyerAssets`. -/
def recordBuy (s : State ι) (m : ι) (buyerAssets boughtNetCredit : ℕ) : State ι :=
  let newNetCredit := s.netCredit m + boughtNetCredit
  let newAmortizedValue := amortizedValue (s.netCredit m) (s.netRate m) (s.ttm m) + buyerAssets
  { s with
    netCredit := Function.update s.netCredit m newNetCredit
    netRate := if 0 < newNetCredit then
        Function.update s.netRate m (netRate newNetCredit newAmortizedValue (s.ttm m))
      else s.netRate }

/-- A buy funded from the vault's idle assets (`fundingAdapter == address(0)`).
`onBuy` accrues at `MidnightAdapter.sol:525` using pre-buy credit and rate (`512-513,769-770`).
The later `allocateInternal` accrual (`VaultV2.sol:542`) reuses `firstTotalAssets` (`627`). -/
def buyState (s : State ι) (m : ι) (buyerAssets boughtNetCredit : ℕ) : State ι :=
  { recordBuy s m buyerAssets boughtNetCredit with
    idle := s.idle - buyerAssets
    totalAssets := newTotalAssets s
    elapsed := 0 }

/-- `withdrawToVault`: Midnight withdraws `assets` of matured or repaid credit, which the vault pulls.
Used by `deallocate` and by self-funded buys.
Neither `MidnightAdapter.sol:658-675` nor `VaultV2.deallocateInternal` (`567-585`) accrues. -/
def withdrawState (s : State ι) (m : ι) (assets : ℕ) : State ι :=
  { s with
    idle := s.idle + assets
    netCredit := Function.update s.netCredit m (s.netCredit m - assets) }

/-- The adapter's `forceDeallocate` branch, including the vault pulling `assets`, before the penalty exit.
The sender funds `assets + settlementFee`, and no rate update or `onSell` runs.
In `lib/midnight/src/Midnight.sol:371-377,399-400`, seller credit decreases by at most the units passed to `take`, while pending-fee reduction offsets that loss.
The adapter passes `assets` as units at tick 0 in `src/adapters/MidnightAdapter.sol:398-425`.
With no bad debt, fee accrual subtracts the same amount from credit and pending fee (`Midnight.sol:805-816`), so the net-credit loss is at most `assets`.
The theorem retains this bound as `soldNetCredit ≤ assets`. -/
def recordForceDeallocate (s : State ι) (m : ι) (assets soldNetCredit : ℕ) : State ι :=
  { s with
    idle := s.idle + assets
    netCredit := Function.update s.netCredit m (s.netCredit m - soldNetCredit) }

/-- A self-funded buy (`fundingAdapter == address(this)`) records the buy, withdraws from the funding market, and pays `buyerAssets` from the vault.
The pre-buy accrual at `MidnightAdapter.sol:525` precedes the funding withdrawal (`528-531`), and the later allocation reuses the cached accrual. -/
def selfFundedBuyState (s : State ι) (m fundingMarket : ι) (buyerAssets boughtNetCredit : ℕ) : State ι :=
  let s₁ := withdrawState (recordBuy s m buyerAssets boughtNetCredit) fundingMarket buyerAssets
  { s₁ with
    idle := s₁.idle - buyerAssets
    totalAssets := newTotalAssets s
    elapsed := 0 }

/-- Shortfall of a sale, as in `onSell`. -/
def shortfall (s : State ι) (m : ι) (sellerAssets soldNetCredit : ℕ) : ℕ :=
  mulDivUp soldNetCredit WAD (WAD + s.netRate m * s.ttm m) - sellerAssets

/-- `onSell` in a market that is not forceSellable: the vault receives `sellerAssets` for `soldNetCredit`; if the sale has a shortfall, visited markets' rates are reduced so that their amortized values grow by their shares (rounded up) of the shortfall, in proportion to their remaining interest.
Markets are visited in index order, stopping once the realized increase covers the shortfall.
`onSell` ends with `deallocate` (`MidnightAdapter.sol:643-649`), whose vault path (`VaultV2.sol:567-585`) does not accrue. -/
def sellState [LinearOrder ι] (s : State ι) (m : ι) (sellerAssets soldNetCredit : ℕ) : State ι :=
  let remainingNetCredit := Function.update s.netCredit m (s.netCredit m - soldNetCredit)
  let sf := shortfall s m sellerAssets soldNetCredit
  let amortizedValues := fun i => amortizedValue (remainingNetCredit i) (s.netRate i) (s.ttm i)
  let totalInterest := ∑ i, (remainingNetCredit i - amortizedValues i)
  let newRate := fun i =>
    if remainingNetCredit i = amortizedValues i then s.netRate i
    else netRate (remainingNetCredit i)
      (amortizedValues i + mulDivUp sf (remainingNetCredit i - amortizedValues i) totalInterest) (s.ttm i)
  let inc := fun i => amortizedValue (remainingNetCredit i) (newRate i) (s.ttm i) - amortizedValues i
  { s with
    idle := s.idle + sellerAssets
    netCredit := remainingNetCredit
    netRate := fun i =>
      if 0 < sf ∧ (∑ j ∈ Finset.univ.filter (· < i), inc j) < sf then newRate i else s.netRate i
    ttm := s.ttm }

/-- The unrounded vault share price without fees.
`previewRedeem` and `previewDeposit` floor an amount times this ratio and its inverse, so redemption previews increase and deposit previews decrease with the price. -/
def sharePrice (s : State ι) : ℚ :=
  (newTotalAssets s + 1 : ℚ) / (s.totalSupply + s.virtualShares)

/-- `previewWithdraw` without fees (`src/VaultV2.sol:671-675`). -/
def previewWithdraw (s : State ι) (assets : ℕ) : ℕ :=
  mulDivUp assets (s.totalSupply + s.virtualShares) (newTotalAssets s + 1)

/-- Accrual followed by the penalty withdrawal to the vault itself (`src/VaultV2.sol:750-798`).
`s` is the post-deallocation state, and the self-transfer leaves `realAssets` unchanged.
If `exit` needs liquidity, assume its extra deallocation preserves this value; this is exact for matured or fully repaid credit withdrawn at face value.
`penaltyExit` checks sufficient total assets and supply, while positive virtual shares remain a constructor invariant. -/
def penaltyExitState (s : State ι) (penalty : ℕ) : State ι :=
  { s with
    totalAssets := newTotalAssets s - penalty
    totalSupply := s.totalSupply - previewWithdraw s penalty
    elapsed := 0 }

/-- Force deallocation followed by accrual and the penalty-share burn.
`VaultV2.sol:794-796` deallocates first, then `withdraw` accrues (`751`) and burns penalty shares (`780-781`).
`accrueInterest` stores the accrued assets and resets `lastUpdate` at `VaultV2.sol:610-618`. -/
def forceDeallocateState (s : State ι) (m : ι) (assets soldNetCredit penalty : ℕ) : State ι :=
  penaltyExitState (recordForceDeallocate s m assets soldNetCredit) penalty

/-- A buy succeeds only when its loss check and idle-funded transfer succeed.
`BuyAtLoss` reverts at `src/adapters/MidnightAdapter.sol:489`.
The transfer of `buyerAssets` fails with insufficient idle assets at `src/VaultV2.sol:544`. -/
def buy (s : State ι) (m : ι) (buyerAssets boughtNetCredit : ℕ) : Option (State ι) :=
  if buyerAssets ≤ boughtNetCredit ∧ buyerAssets ≤ s.idle then
    some (buyState s m buyerAssets boughtNetCredit)
  else none

/-- A withdrawal succeeds only when its modeled credit subtraction is defined.
Midnight's actual checked subtraction requires `units ≤ credit` at `lib/midnight/src/Midnight.sol:486`.
The modeled `assets ≤ netCredit` condition is stronger, so this abstraction covers fewer withdrawal cases. -/
def withdraw (s : State ι) (m : ι) (assets : ℕ) : Option (State ι) :=
  if assets ≤ s.netCredit m then some (withdrawState s m assets) else none

/-- A self-funded buy propagates the funding withdrawal's revert.
`BuyAtLoss` reverts at `src/adapters/MidnightAdapter.sol:489`.
The funding withdrawal at `MidnightAdapter.sol:530` uses the stronger modeled check documented by `withdraw`. -/
def selfFundedBuy (s : State ι) (m fundingMarket : ι)
    (buyerAssets boughtNetCredit : ℕ) : Option (State ι) := do
  if buyerAssets ≤ boughtNetCredit then
    let s₁ ← withdraw (recordBuy s m buyerAssets boughtNetCredit) fundingMarket buyerAssets
    pure { s₁ with
      idle := s₁.idle - buyerAssets
      totalAssets := newTotalAssets s
      elapsed := 0 }
  else none

/-- A sale succeeds only when credit remains nonnegative and the shortfall can be covered.
Seller credit is checked when reduced in `lib/midnight/src/Midnight.sol:400`; the model excludes debt-increasing sales.
`ShortfallTooHigh` checks `shortfall ≤ totalInterest` at `src/adapters/MidnightAdapter.sol:619`, using post-sale net credits (`610-617`).
The on-chain check runs only for positive shortfall; for zero shortfall it holds automatically. -/
def sell [LinearOrder ι] (s : State ι) (m : ι)
    (sellerAssets soldNetCredit : ℕ) : Option (State ι) :=
  let remainingNetCredit := Function.update s.netCredit m (s.netCredit m - soldNetCredit)
  let totalInterest := ∑ i, (remainingNetCredit i -
    amortizedValue (remainingNetCredit i) (s.netRate i) (s.ttm i))
  if soldNetCredit ≤ s.netCredit m ∧
      shortfall s m sellerAssets soldNetCredit ≤ totalInterest then
    some (sellState s m sellerAssets soldNetCredit)
  else none

/-- The penalty exit reverts when either checked accounting subtraction underflows.
The asset subtraction is at `src/VaultV2.sol:781`.
The share burn at `VaultV2.sol:780` checks total supply at `873`. -/
def penaltyExit (s : State ι) (penalty : ℕ) : Option (State ι) :=
  if penalty ≤ newTotalAssets s ∧ previewWithdraw s penalty ≤ s.totalSupply then
    some (penaltyExitState s penalty)
  else none

/-- Force deallocation propagates the penalty exit's checked-subtraction reverts.
The reduce-only take at `src/adapters/MidnightAdapter.sol:407,425` rejects seller debt increases at `lib/midnight/src/Midnight.sol:380-382`.
The model checks the resulting net-credit decrease against the starting net credit. -/
def forceDeallocate (s : State ι) (m : ι)
    (assets soldNetCredit penalty : ℕ) : Option (State ι) :=
  if soldNetCredit ≤ s.netCredit m then
    penaltyExit (recordForceDeallocate s m assets soldNetCredit) penalty
  else none

end MidnightAdapterProofs
