This folder contains the formal verification of Vault V2 using CVL, Certora's Verification Language.

Vault V2 is a non-custodial ERC-4626 vault that allocates assets across markets through adapters. See the repository [`README`](../README.md) and [`src/VaultV2.sol`](../src/VaultV2.sol) for the protocol itself. The verified properties are listed below by theme, followed by the verification setup.

# Verified properties

## Core state and accounting

Global invariants and the accounting effects of each entry point.

* [`Invariants.spec`](specs/Invariants.spec) collects the core state invariants. Variables stay within their bounds; a non-zero fee always has a recipient; and the zero address has no shares. Total supply equals the sum of all balances, every allocation fits in an `int256`, virtual shares stay within their configured range. The adapter list and `isAdapter` mapping remain mutually consistent, list entries are distinct, and, assuming an add-only registry, every adapter remains in the configured registry.
* [`TotalAssetsChange.spec`](specs/TotalAssetsChange.spec) pins down changes to `_totalAssets` when no interest accrues. Deposits and mints add exactly the transferred or previewed assets, withdrawals and redemptions subtract exactly the withdrawn or previewed assets, and `forceDeallocate` subtracts exactly its rounded-up penalty. Every other entry point leaves `_totalAssets` unchanged.
* [`TotalAssetsIsUpToDate.spec`](specs/TotalAssetsIsUpToDate.spec) checks that every state-changing entry point other than `accrueInterest` updates `_totalAssets` before reading it.
* [`AllocationVaultV2.spec`](specs/AllocationVaultV2.spec) checks that allocations change only through ERC-4626 entry and exit functions, `allocate`, `deallocate`, or `forceDeallocate`. An ERC-4626 operation can change allocations only when a liquidity adapter is set.
* [`AllocationsHierarchy.spec`](specs/AllocationsHierarchy.spec) checks the leaf-group structure used by adapter ids. A group's allocation always equals the sum of its leaf allocations and is therefore at least every individual leaf allocation.

## Shares and ERC-4626 behavior

Share-price movement, rounding, previews, and equivalent entry points.

* [`ExchangeRate.spec`](specs/ExchangeRate.spec) checks that the seeded vault's share price does not decrease when the management fee is zero and interest has already been accrued. It separately shows that realizing a loss does not increase the share price and that deposit, mint, withdraw, and redeem use the tight protocol-favoring rounding direction.
* [`PreviewFunctions.spec`](specs/PreviewFunctions.spec) checks that `previewDeposit`, `previewMint`, `previewWithdraw`, and `previewRedeem` return exactly the value produced by the corresponding successful ERC-4626 operation. A preview never reverts when its corresponding operation can succeed.
* [`EntrypointEquivalence.spec`](specs/EntrypointEquivalence.spec) checks that deposit and mint pass identical values to the internal entry path when their inputs and outputs match. It establishes the analogous equivalence between withdraw and redeem for the internal exit path.
* [`RoundTrip.spec`](specs/RoundTrip.spec) checks the rounding inequalities between asset/share conversions and every relevant composition of deposit, mint, withdraw, and redeem previews. These round trips cannot create value through inconsistent rounding.

## Adapter ids and allocation tracking

Adapters report stable risk ids and keep the vault's allocation accounting aligned with their underlying positions.

* [`IdsMorphoMarketV1AdapterV2.spec`](specs/IdsMorphoMarketV1AdapterV2.spec) checks that the Morpho Market V1 adapter returns three deterministic and pairwise-distinct ids for a given market, including the id derived from the adapter address. The ids returned by `allocate` and `deallocate` match the adapter's reference list.
* [`IdsMorphoVaultV1Adapter.spec`](specs/IdsMorphoVaultV1Adapter.spec) checks the same properties for the Morpho Vault V1 adapter's single, constant adapter id.
* [`AllocationMorphoMarketV1AdapterV2.spec`](specs/AllocationMorphoMarketV1AdapterV2.spec) checks that allocation and deallocation change every returned id by exactly the change reported by the Morpho Market V1 adapter and leave all other ids untouched. After either call, the adapter's allocation equals its expected supply assets. It also bounds expected supply assets and relates the adapter's internal supply-share accounting to its actual Morpho position.
* [`AllocationMorphoVaultV1Adapter.spec`](specs/AllocationMorphoVaultV1Adapter.spec) checks the equivalent allocation updates for the Morpho Vault V1 adapter. After allocation or deallocation, the reported allocation equals the assets previewed from the adapter's MetaMorpho shares.
* [`ChangesMorphoMarketV1AdapterV2.spec`](specs/ChangesMorphoMarketV1AdapterV2.spec) and [`ChangesMorphoVaultV1Adapter.spec`](specs/ChangesMorphoVaultV1Adapter.spec) check each adapter's returned allocation change. Allocating and deallocating zero assets report the same change from the same state, and no reported change can make the current allocation negative.
* [`MarketIds.spec`](specs/MarketIds.spec) checks the Morpho Market V1 adapter's active-market list. Its entries are distinct, and a market with zero allocation is absent from the list.

## Caps and configuration delays

Risk limits and timelocked configuration cannot be bypassed.

* [`RelativeCaps.spec`](specs/RelativeCaps.spec) checks that state-changing functions preserve every relative cap except the operations that may legitimately move outside it: interest or loss accrual, exits, cap decreases, and deallocation. The latter can increase a recorded allocation while realizing interest, whereas allocation would reject the same cap excess.
* [`EarliestTime.spec`](specs/EarliestTime.spec) checks the three ways a timelocked call can become executable: an existing submission, a fresh submission plus the current timelock, or a pending timelock decrease plus the new delay. For the covered configuration calls, the earliest execution time cannot move backward and the call cannot succeed before it.
* [`AbdicatedFunctions.spec`](specs/AbdicatedFunctions.spec) checks that an abdicated timelocked function cannot be called, that abdication is permanent, and that each affected configuration value remains unchanged in the direction the abdicated function would have modified it.
* [`Immutability.spec`](specs/Immutability.spec) checks that every `DELEGATECALL` targets the vault itself, preventing delegation to arbitrary implementation code.

## Authorization, input validation, and liveness

Privileged actions enforce their roles, while authorized accounts retain the operations needed to operate or derisk the vault.

* [`Reverts.spec`](specs/Reverts.spec) checks the revert conditions or required input validation for timelocked configuration, ownership and metadata changes, submission and revocation, cap decreases, `forceDeallocate`, liquidity-adapter and max-rate changes, and share transfers. This covers role checks, timelocks and abdication, gates, allowances, balances, bounds, and non-payable calls.
* [`AllocateDeallocateReverts.spec`](specs/AllocateDeallocateReverts.spec) checks the exact authorization-level revert conditions for `allocate` and `deallocate`, assuming the adapter returns unique ids and allocation changes that satisfy the required cap and integer bounds. Allocation requires an allocator and a registered adapter; deallocation accepts an allocator or sentinel and also requires a registered adapter.
* [`AllocateDeallocateInputValidation.spec`](specs/AllocateDeallocateInputValidation.spec) checks that allocation rejects any returned id with a zero absolute cap and deallocation rejects any returned id with a zero recorded allocation, preventing interaction with unknown markets.
* [`AccrueInterestReverts.spec`](specs/AccrueInterestReverts.spec) gives sufficient conditions under which `accrueInterestView` and `accrueInterest` do not revert. It bounds the returned total assets and fee shares and checks that a zero performance or management fee produces zero corresponding fee shares.
* [`Liveness.spec`](specs/Liveness.spec) checks that a curator or sentinel can reduce an absolute or relative cap to zero and that the owner can set the owner, curator, and sentinel status without reverting.
* [`OwnerSafety.spec`](specs/OwnerSafety.spec) additionally checks the post-state of owner actions: the owner can always transfer ownership, replace the curator, and add or remove a sentinel, and each call writes the requested value.
* [`SentinelLiveness.spec`](specs/SentinelLiveness.spec) checks that a sentinel can always revoke pending data and decrease absolute or relative caps.
* [`SentinelLivenessDeallocateMarketV1.spec`](specs/SentinelLivenessDeallocateMarketV1.spec) and [`SentinelLivenessDeallocateVaultV1.spec`](specs/SentinelLivenessDeallocateVaultV1.spec) check that a sentinel can deallocate through either supported adapter when the underlying withdrawal succeeds, the relevant allocations are positive, and the adapter's accounting result stays in range.
* [`ForceDeallocate.spec`](specs/ForceDeallocate.spec) checks that `forceDeallocate` with zero requested assets remains callable to refresh allocation accounting, assuming the gates admit the exit, the adapter returns valid ids and changes, interest accrual is live, and the vault's accounting values are bounded.
* [`RemoveMarketLiveness.spec`](specs/RemoveMarketLiveness.spec) checks that a liquid Morpho Market V1 position can be fully deallocated. Deallocating its expected supply assets reduces that value to zero, and a zero-allocation market is removed from the adapter's active-market list.

## Gates and token transfers

Shares and assets move only through permitted paths and by the exact requested amounts.

* [`Gates.spec`](specs/Gates.spec) checks that a user who cannot receive shares never gains them and a user who cannot send shares never loses them. For asset transfers initiated by the vault, balances cannot increase or decrease contrary to the receive-assets or send-assets gate; adapter-initiated transfers are outside this property.
* [`TokensNoAdapter.spec`](specs/TokensNoAdapter.spec) checks exact sender, receiver, and vault asset-balance changes on deposit and withdrawal when no liquidity adapter is configured.
* [`TokensMorphoMarketV1AdapterV2.spec`](specs/TokensMorphoMarketV1AdapterV2.spec) checks the same flows through a Morpho Market V1 liquidity adapter. Deposits move assets from the sender into Morpho without leaving balances on the vault or adapter; withdrawals consume idle vault assets first, then Morpho liquidity, and pay the receiver exactly.
* [`TokensMorphoVaultV1Adapter.spec`](specs/TokensMorphoVaultV1Adapter.spec) checks those token flows through a Morpho Vault V1 liquidity adapter and its underlying Morpho markets.
* [`SkimMorphoMarketV1AdapterV2.spec`](specs/SkimMorphoMarketV1AdapterV2.spec) checks that `skim` transfers only tokens already held by the Morpho Market V1 adapter and does not change its reported assets. It also checks that changing the skim recipient follows the adapter's timelock and abdication conditions.
* [`SkimMorphoVaultV1Adapter.spec`](specs/SkimMorphoVaultV1Adapter.spec) checks the corresponding skim accounting for the Morpho Vault V1 adapter and requires the vault owner, with no ETH value, to change the skim recipient.

## External calls and reentrancy

The vault does not expose an untrusted callback after entering an unsafe intermediate state.

* [`Reentrancy.spec`](specs/Reentrancy.spec) checks that state-changing entry points make no external calls outside the vault itself, registered supported adapters, the asset token, Morpho Market V1, and MetaMorpho V1. The token and underlying markets are modeled as trusted not to reenter.
* [`ReentrancyView.spec`](specs/ReentrancyView.spec) checks read-only reentrancy ordering: after an external static call follows a storage write, the vault performs no later storage write. Calls to the asset's `balanceOf`, adapters' `realAssets`, gate checks, and the adapter registry are the explicitly modeled view dependencies. The rule excludes `forceDeallocate`, which composes the separately analyzed `deallocate` and `withdraw` paths.

# Verification setup

Verification is performed according to the following modeling conventions:

* loops are bounded according to each configuration file, using `loop_iter` and, where enabled, `optimistic_loop`; hashing loops are similarly modeled with `optimistic_hashing`;
* vault-level properties summarize adapter calls with the id, cap, allocation, and liveness postconditions required by the rule, while adapter-level properties link the concrete adapters to Morpho Market V1 or MetaMorpho V1 harnesses;
* ERC-20 behavior is checked against the [`ERC20Standard`](https://github.com/morpho-org/metamorpho/blob/00da9ad27da8051bce663eeac02f3b9c0c0aa8d8/certora/dispatch/ERC20Standard.sol), [`ERC20NoRevert`](https://github.com/morpho-org/metamorpho/blob/00da9ad27da8051bce663eeac02f3b9c0c0aa8d8/certora/dispatch/ERC20NoRevert.sol), and [`ERC20USDT`](https://github.com/morpho-org/metamorpho/blob/00da9ad27da8051bce663eeac02f3b9c0c0aa8d8/certora/dispatch/ERC20USDT.sol) models. These cover standard reverting tokens, false-returning tokens, and tokens that omit return values; fee-on-transfer and reentrant tokens are not supported;
* external market rates, balances, and view calls are summarized only where their concrete behavior is not the subject of the property. The specifications state the necessary bounds and non-reversion assumptions at those summaries;
* revert-condition rules that evaluate a helper contract before the target call may omit trivial failures, such as a non-zero `msg.value`, when that helper call itself reverts. This limitation applies to the timelocked-function rule in [`Reverts.spec`](specs/Reverts.spec) and the skim-recipient rule in [`SkimMorphoMarketV1AdapterV2.spec`](specs/SkimMorphoMarketV1AdapterV2.spec);
* `multicall` is removed in properties that reason about a single entry point. Because it only calls the vault itself, invariants preserved by every individual entry point are preserved by induction across a multicall;
* the reentrancy proofs trust the configured ERC-20 token, Morpho Market V1, and MetaMorpho V1 not to reenter the vault. Adapter calls are restricted to registered instances of the two verified adapter implementations;
* both rules in [`EarliestTime.spec`](specs/EarliestTime.spec) exclude `decreaseTimelock` because of a prover limitation.

The [`confs`](confs) folder contains one configuration for every specification. Shared CVL utilities and Solidity harnesses are in [`helpers`](helpers).

# Getting started

Install the `certora-cli` package with `pip install certora-cli`. To verify a spec, pass its configuration file in [`certora/confs`](confs) to `certoraRun`. This requires a valid Certora key in the `CERTORAKEY` environment variable. The complete suite uses `solc-0.8.19`, `solc-0.8.21`, `solc-0.8.26`, and `solc-0.8.28`; the compiler versions required by a particular job are listed in its configuration.

Additional arguments can select a specific rule. For example, from the repository root:

```sh
certoraRun certora/confs/Invariants.conf --rule totalSupplyIsSumOfBalances
```

# Acknowledgments

Some rules and invariants are derived from work by ChainSecurity during its VaultV2 audit.
