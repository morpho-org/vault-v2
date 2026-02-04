This folder contains the formal verification of Vault V2 using CVL, Certora's Verification Language.

The core concepts of Vault V2 are described in the [README](../README.md) at the root of the repository.
These concepts have been verified using CVL.
We first give a [high-level description](#high-level-description) of the verification and then describe the [folder and file structure](#folder-and-file-structure) of the specification files.

# High-level description

Vault V2 enables anyone to create non-custodial vaults that allocate assets into different markets via adapters.
Depositors earn from the underlying markets without having to actively manage their position.

## ERC20 tokens and transfers

Vault V2 relies on the fact that the underlying asset respects the ERC20 standard.
In particular, in case of a transfer, it is assumed that the balance of the vault increases or decreases (depending if it's the recipient or the sender) of the amount transferred.

The verification is done for the most common implementations of the ERC20 standard, for which we distinguish three different implementations:

- Standard compliant versions that revert in case of insufficient funds or insufficient allowance.
- Standard compliant versions that do not revert (and return false instead).
- Non-standard implementations like USDT which omit the return value.

The file [TokensNoAdapter.spec](specs/TokensNoAdapter.spec) checks that token balances change as expected on deposit and withdraw operations.

```solidity
rule depositTokenChange(env e, uint256 assets, address receiver) {
    // ...
    deposit(e, assets, receiver);
    // ...
    assert assert_uint256(balanceVaultV2After - balanceVaultV2Before) == assets;
    assert assert_uint256(balanceSenderBefore - balanceSenderAfter) == assets;
}
```

## Adapters and allocations

Vault V2 allocates assets to underlying markets via separate contracts called adapters.
The verification ensures that adapters are properly tracked and that allocations can only be modified through specific functions.

The file [AllocationVaultV2.spec](specs/AllocationVaultV2.spec) verifies that only the expected functions can change allocations.

```solidity
rule functionsChangingAllocation(env e, method f, calldataarg args)
filtered {
    f -> !f.isView &&
    f.selector != sig:deposit(uint256,address).selector &&
    f.selector != sig:mint(uint256,address).selector &&
    // ...
}
{
    bytes32 id;
    uint256 allocationPre = allocation(id);
    f(e, args);
    assert allocation(id) == allocationPre;
}
```

Additionally, the [MarketIds.spec](specs/MarketIds.spec) file verifies that market IDs are properly maintained.

```solidity
strong invariant marketIdsWithNoAllocationIsNotInMarketIds()
    forall bytes32 marketId.
    forall uint256 i. i < currentContract.marketIds.length => ghostAllocation[marketId] == 0 => currentContract.marketIds[i] != marketId
```

## Shares and exchange rate

When depositing into Vault V2, shares are minted to represent the user's position.
The share price is verified to be monotonically increasing (except due to management fees or loss realization).
This ensures that the vault cannot be exploited through share price manipulation.

The file [ExchangeRate.spec](specs/ExchangeRate.spec) checks this property with the following rule.

```solidity
rule sharePriceIsIncreasing(method f, env e, calldataarg a) {
    // ...
    mathint assetsBefore = assets();
    mathint sharesBefore = shares();

    f(e, a);

    assert assetsBefore * shares() <= assets() * sharesBefore;
}
```

The specification also verifies optimal rounding on deposit, withdraw, mint, and redeem operations, ensuring that small errors are in favor of the protocol.

## Timelocks and earliest execution time

Curator configuration changes are timelockable, meaning that an action must be submitted first, and only when the timelock has passed can it be executed.
This mechanism is critical for the non-custodial guarantees of the vault.

The file [EarliestTime.spec](specs/EarliestTime.spec) verifies that the earliest execution time is monotonically non-decreasing.

```solidity
rule earliestExecutionTimeIncreases(env e, method f, calldataarg args) {
    // ...
    mathint earliestTimeBefore = earliestExecutionTimeFromData(blockTimestampBefore, data);
    f(e, args);
    mathint earliestTimeAfter = earliestExecutionTimeFromData(e.block.timestamp, data);
    assert earliestTimeAfter >= earliestTimeBefore;
}
```

## Gates

Vault V2 can use external gate contracts to control share transfers and asset deposits/withdrawals.
The file [Gates.spec](specs/Gates.spec) verifies that the gating mechanism works correctly.

```solidity
rule cantReceiveShares(env e, method f, calldataarg args, address user) {
    require (!canReceiveShares(user), "setup gating");
    uint256 sharesBefore = balanceOf(user);
    f(e, args);
    assert balanceOf(user) <= sharesBefore;
}
```

This ensures that users who are not allowed to receive shares will never have their share balance increase.

## Caps

The funds allocation of the vault is constrained by an id-based caps system.
Relative caps only constrain allocations, so they can be exceeded because of withdrawals from the vault.

The file [RelativeCaps.spec](specs/RelativeCaps.spec) verifies that relative caps are respected.

```solidity
rule relativeCapValidity(env e, method f, calldataarg args) {
    // ...
    assert currentContract.caps[id].relativeCap < Utils.wad() =>
    currentContract.caps[id].allocation <= (firstTotalAssetsAfter * currentContract.caps[id].relativeCap) / Utils.wad();
}
```

## Authorization and owner safety

Vault V2 defines different roles: owner, curator, sentinels, and allocators.
The verification ensures that only authorized accounts can perform their respective actions.

The file [OwnerSafety.spec](specs/OwnerSafety.spec) verifies that the owner can always perform their expected operations.

```solidity
rule ownerCanChangeOwner(env e, address newOwner) {
    require (e.msg.sender == currentContract.owner, "setup the call to be performed by the owner");
    require (e.msg.value == 0, "setup the call to have no ETH value");
    setOwner@withrevert(e, newOwner);
    assert !lastReverted;
    assert owner() == newOwner;
}
```

## Sentinel liveness

Sentinels have the ability to revoke pending timelocked actions and decrease caps.
The file [SentinelLiveness.spec](specs/SentinelLiveness.spec) verifies that sentinels can always perform these safety operations.

```solidity
rule sentinelCanRevoke(env e, bytes data) {
    require executableAt(data) != 0, "assume that data is pending";
    require isSentinel(e.msg.sender), "setup call to be performed by a sentinel";
    require e.msg.value == 0, "setup call to have no ETH value";
    revoke@withrevert(e, data);
    assert !lastReverted;
    assert executableAt(data) == 0;
}
```

## Abdication

Configuration can be abdicated, meaning it cannot be changed anymore.
The file [AbdicatedFunctions.spec](specs/AbdicatedFunctions.spec) verifies that abdicated functions cannot be called and that abdication is permanent.

```solidity
rule abdicatedFunctionsCantBeCalled(env e, method f, calldataarg args) filtered { f -> functionIsTimelocked(f) } {
    require abdicated(to_bytes4(f.selector));
    f@withrevert(e, args);
    assert lastReverted;
}

rule abdicatedCantBeDeabdicated(env e, method f, calldataarg args, bytes4 selector) {
    require abdicated(selector);
    f(e, args);
    assert abdicated(selector);
}
```

## Other safety properties

### Invariants and ranges

The file [Invariants.spec](specs/Invariants.spec) checks various invariants about the protocol state, including:

- Fee bounds are respected (performance fee and management fee).
- Fee recipients are set when fees are non-zero.
- Total supply equals the sum of all balances.
- Adapters are properly registered and distinct.
- Virtual shares bounds are maintained.

```solidity
strong invariant performanceFeeBound()
    performanceFee() <= Utils.maxPerformanceFee();

strong invariant totalSupplyIsSumOfBalances()
    totalSupply() == sumOfBalances;
```

### Immutability

The file [Immutability.spec](specs/Immutability.spec) verifies that the contract is truly immutable and cannot delegate calls to arbitrary addresses.

### Input validation and revert conditions

The file [Reverts.spec](specs/Reverts.spec) checks the exact conditions under which functions revert, ensuring proper input validation.

```solidity
rule setOwnerRevertCondition(env e, address newOwner) {
    address owner = owner();
    setOwner@withrevert(e, newOwner);
    assert lastReverted <=> e.msg.value != 0 || e.msg.sender != owner;
}
```

## Liveness properties

On top of verifying that the protocol is secured, the verification also proves that it is usable.
Such properties are called liveness properties.

The file [Liveness.spec](specs/Liveness.spec) checks that authorized users can always perform their expected operations.

```solidity
rule livenessDecreaseAbsoluteCapZero(env e, bytes idData) {
    require e.msg.sender == curator() || isSentinel(e.msg.sender);
    require e.msg.value == 0;
    decreaseAbsoluteCap@withrevert(e, idData, 0);
    assert !lastReverted;
}
```

The file [RemoveMarketLiveness.spec](specs/RemoveMarketLiveness.spec) verifies that it is always possible to deallocate from a market and remove it from the adapter.

## ERC-4626 compliance

The file [PreviewFunctions.spec](specs/PreviewFunctions.spec) verifies that the preview functions accurately predict the results of the corresponding operations, as required by the ERC-4626 standard.

```solidity
rule previewDepositValue(env e, uint256 assets, address onBehalf) {
    uint256 previewDepositValue = previewDeposit(e, assets);
    uint256 depositValue = deposit(e, assets, onBehalf);
    assert previewDepositValue == depositValue;
}
```

The file [TotalAssetsChange.spec](specs/TotalAssetsChange.spec) verifies that total assets change correctly on deposit, withdraw, mint, and redeem operations.

## Protection against common attack vectors

Other common and known attack vectors are verified to not be possible on Vault V2.

### Reentrancy

Reentrancy is a common attack vector that happens when a call to a contract allows, when in a temporary state, to call the same contract again.
The Vault V2 contract is verified to not be vulnerable to reentrancy attacks.

The file [Reentrancy.spec](specs/Reentrancy.spec) checks that there are no untrusted external calls.

```solidity
rule reentrancySafe(method f, env e, calldataarg data) {
    require (!ignoredCall && !hasCall, "set up the initial ghost state");
    f(e,data);
    assert !hasCall;
}
```

### Extraction of value

The Vault V2 protocol uses a conservative approach to handle arithmetic operations.
Rounding is done such that potential errors are in favor of the protocol, which ensures that it is not possible to extract value from other users.

This is verified in [ExchangeRate.spec](specs/ExchangeRate.spec) with the optimal rounding rules.

# Folder and file structure

The [`certora/specs`](specs) folder contains the following files:

- [`AbdicatedFunctions.spec`](specs/AbdicatedFunctions.spec) checks that abdicated functions cannot be called and that abdication is permanent for each function.
- [`AllocateDeallocateInputValidation.spec`](specs/AllocateDeallocateInputValidation.spec) checks input validation for allocate and deallocate functions.
- [`AllocateDeallocateReverts.spec`](specs/AllocateDeallocateReverts.spec) checks the revert conditions for allocate and deallocate functions.
- [`AllocationMorphoMarketV1AdapterV2.spec`](specs/AllocationMorphoMarketV1AdapterV2.spec) checks allocation properties specific to the Morpho Market V1 Adapter V2.
- [`AllocationMorphoVaultV1Adapter.spec`](specs/AllocationMorphoVaultV1Adapter.spec) checks allocation properties specific to the Morpho Vault V1 Adapter.
- [`AllocationVaultV2.spec`](specs/AllocationVaultV2.spec) checks that only specific functions can change allocations.
- [`ChangesMorphoMarketV1AdapterV2.spec`](specs/ChangesMorphoMarketV1AdapterV2.spec) checks state changes for the Morpho Market V1 Adapter V2.
- [`ChangesMorphoVaultV1Adapter.spec`](specs/ChangesMorphoVaultV1Adapter.spec) checks state changes for the Morpho Vault V1 Adapter.
- [`EarliestTime.spec`](specs/EarliestTime.spec) checks that the earliest execution time for timelocked functions is monotonically non-decreasing.
- [`EntrypointEquivalence.spec`](specs/EntrypointEquivalence.spec) checks equivalence properties for entrypoint functions.
- [`ExchangeRate.spec`](specs/ExchangeRate.spec) checks that the share price is monotonically increasing and that rounding is optimal.
- [`Gates.spec`](specs/Gates.spec) checks that the gating mechanism correctly restricts share and asset transfers.
- [`IdsMorphoMarketV1AdapterV2.spec`](specs/IdsMorphoMarketV1AdapterV2.spec) checks ID management for the Morpho Market V1 Adapter V2.
- [`IdsMorphoVaultV1Adapter.spec`](specs/IdsMorphoVaultV1Adapter.spec) checks ID management for the Morpho Vault V1 Adapter.
- [`Immutability.spec`](specs/Immutability.spec) checks that the contract is immutable and cannot delegate calls to arbitrary addresses.
- [`Invariants.spec`](specs/Invariants.spec) checks various invariants about the protocol state, including fee bounds, total supply accounting, and adapter registration.
- [`Liveness.spec`](specs/Liveness.spec) checks that authorized users can always perform their expected operations.
- [`MarketIds.spec`](specs/MarketIds.spec) checks that market IDs are properly maintained and distinct.
- [`OwnerSafety.spec`](specs/OwnerSafety.spec) checks that the owner can always perform their expected operations.
- [`PreviewFunctions.spec`](specs/PreviewFunctions.spec) checks ERC-4626 compliance by verifying that preview functions accurately predict operation results.
- [`Reentrancy.spec`](specs/Reentrancy.spec) checks that there are no untrusted external calls, ensuring reentrancy safety.
- [`ReentrancyView.spec`](specs/ReentrancyView.spec) checks reentrancy safety for view functions.
- [`RelativeCaps.spec`](specs/RelativeCaps.spec) checks that relative caps are properly enforced on allocations.
- [`RemoveMarketLiveness.spec`](specs/RemoveMarketLiveness.spec) checks that it is always possible to deallocate from a market and remove it.
- [`Reverts.spec`](specs/Reverts.spec) checks the exact revert conditions for various functions, ensuring proper input validation.
- [`SentinelLiveness.spec`](specs/SentinelLiveness.spec) checks that sentinels can always revoke pending actions and decrease caps.
- [`SentinelLivenessDeallocateMarketV1.spec`](specs/SentinelLivenessDeallocateMarketV1.spec) checks sentinel liveness for deallocating from Market V1.
- [`SentinelLivenessDeallocateVaultV1.spec`](specs/SentinelLivenessDeallocateVaultV1.spec) checks sentinel liveness for deallocating from Vault V1.
- [`TokensMorphoMarketV1AdapterV2.spec`](specs/TokensMorphoMarketV1AdapterV2.spec) checks token transfer properties for the Morpho Market V1 Adapter V2.
- [`TokensMorphoVaultV1Adapter.spec`](specs/TokensMorphoVaultV1Adapter.spec) checks token transfer properties for the Morpho Vault V1 Adapter.
- [`TokensNoAdapter.spec`](specs/TokensNoAdapter.spec) checks token balance changes on deposit and withdraw operations without adapters.
- [`TotalAssetsChange.spec`](specs/TotalAssetsChange.spec) checks that total assets change correctly on ERC-4626 operations.
- [`TotalAssetsIsUpToDate.spec`](specs/TotalAssetsIsUpToDate.spec) checks that total assets tracking is kept up to date.

The [`certora/confs`](confs) folder contains a configuration file for each corresponding specification file.

The [`certora/helpers`](helpers) folder contains contracts and specifications that enable the verification of Vault V2.
Notably, this includes:
- [ERC20Helper.sol](helpers/ERC20Helper.sol) for handling ERC20 balance queries.
- [Utils.sol](helpers/Utils.sol) for utility functions and constants.
- [UtilityVault.spec](helpers/UtilityVault.spec) and [UtilityAdapters.spec](helpers/UtilityAdapters.spec) for common specification helpers.

# Getting started

Install `certora-cli` package with `pip install certora-cli`.
To verify specification files, pass to `certoraRun` the corresponding configuration file in the [`certora/confs`](confs) folder.
It requires having set the `CERTORAKEY` environment variable to a valid Certora key.
You can also pass additional arguments, notably to verify a specific rule.
For example, at the root of the repository:

```
certoraRun certora/confs/Invariants.conf --rule totalSupplyIsSumOfBalances
```

# Acknowledgments

Some rules and invariants are derived from those written by the Chainsecurity team during their audit of this repository.