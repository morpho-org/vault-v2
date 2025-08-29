# Vault v2

Morpho Vault v2 enables anyone to create [non-custodial](#non-custodial-guarantees) vaults that allocate assets to any protocols, including but not limited to Morpho Market v1, Morpho Market v2, and Morpho Vault v1.
Depositors of Morpho Vault v2 earn from the underlying protocols without having to actively manage the risk of their position.
Management of deposited assets is the responsibility of a set of different roles (owner, curator and allocators).
The active management of invested positions involves enabling and allocating liquidity to protocols.

[Morpho Vault v2](./src/VaultV2.sol) is [ERC-4626](https://eips.ethereum.org/EIPS/eip-4626) and [ERC-2612](https://eips.ethereum.org/EIPS/eip-2612) compliant.
The [VaultV2Factory](./src/VaultV2Factory.sol) deploys instances of Vaults v2.
All the contracts are immutable.

## Overview

### Adapters

Vaults can allocate assets to arbitrary protocols and markets via adapters.
The curator enables adapters to hold positions on behalf of the vault.
Adapters are also used to know how much these investments are worth (interest and loss realization).
Because adapters hold positions in protocols where assets are allocated, they are susceptible to accrue rewards for those protocols.
To ensure that those rewards can be retrieved, each adapter has a skim function that can be called by the vault's owner.

Adapters for the following protocols are currently available:

- [Morpho Market v1](./src/adapters/MorphoMarketV1Adapter.sol).
  This adapter allocates to any Morpho Market v1, constrained by the allocation caps (see [Id system](#id-system) below).
  The adapter holds a position on each respective market, on behalf of the vault v2.
- [Morpho Vault v1](./src/adapters/MorphoVaultV1Adapter.sol).
  This adapter allocates to a fixed Morpho Vault v1 (v1.0 and v1.1).
  The adapter holds shares of the corresponding Morpho Vault v1 (v1.0 and v1.1) on behalf of the vault v2.

A Morpho Market v2 adapter will be released together with Market v2.

### Id system

The funds allocation of the vault is constrained by an id system.
An id is an abstract identifier for a common risk factor of some markets (a collateral, an oracle, a protocol, etc.).
Allocation on markets with a common id is limited by absolute caps and relative caps.
Note that relative caps are "soft" because they are not checked on withdrawals, they only constrain new allocations.
The curator ensures the consistency of the id system by:

- setting caps for the ids according to an estimation of risk;
- setting adapters that return consistent ids.

The ids of Morpho v1 lending markets could be for example the market parameters `(LoanToken, CollateralToken, Oracle, IRM, LLTV)` and `CollateralToken` alone.
A vault could be set up to enforce the following caps:

- `(loanToken, stEth, chainlink, irm, 86%)`: 10M
- `(loanToken, stETH, redstone, irm, 86%)`: 10M
- `stETH`: 15M

This would ensure that the vault never has more than 15M exposure to markets with stETH as collateral, and never more than 10M exposure to an individual market.

### Liquidity

The allocator is responsible for ensuring that users can withdraw their assets at any time.
This is done by managing the available idle liquidity and an optional liquidity adapter.

When users withdraw assets, the idle assets are taken in priority.
If there is not enough idle liquidity, liquidity is taken from the liquidity adapter.
When defined, the liquidity adapter is also used to forward deposited funds.

A typical liquidity adapter would allow deposits/withdrawals to go through a very liquid Market v1.

### Non-custodial guarantees

Non-custodial guarantees come from [in-kind redemptions](#in-kind-redemptions-with-forcedeallocate) and [timelocks](#curator-timelocks).
These mechanisms allow users to withdraw their assets before any critical configuration change takes effect.

### In-kind redemptions with `forceDeallocate`

To guarantee exits even in the absence of assets immediately available for withdrawal, the permissionless `forceDeallocate` function allows anyone to move assets from an adapter to the vault's idle assets.

Users can redeem in-kind thanks to the `forceDeallocate` function: flashloan liquidity, supply it to an adapter's market, and withdraw the liquidity through `forceDeallocate` before repaying the flashloan.
This reduces their position in the vault and increases their position in the underlying market.

A penalty for using forceDeallocate can be set per adapter, of up to 2%.
This disincentivizes the manipulation of allocations, in particular of relative caps which are not checked on withdrawals.
Note that the only friction to deallocating an adapter with a 0% penalty is the associated gas cost.

### Gates

Vaults v2 can use external gate contracts to control share transfer, vault asset deposit, and vault asset withdrawal.

If a gate is not set, its corresponding operations are not restricted.

Gate changes can be timelocked.
By setting the timelock to `type(uint256).max`, a curator can commit to an irreversible gate setup.

Four gates are defined:

**Receive shares gate** (`receiveSharesGate`): Controls the permission to receive shares.

Upon `deposit`/`mint`, `transfer`/`transferFrom`, and interest accrual (for both fee recipients), `canReceiveShares` must return `true` for the shares recipient if the gate is set.

This gate is critical because it can prevent depositors from getting back their shares deposited on other contracts. Also, if it reverts and there is a non-zero fee, interest accrual reverts.

**Send shares gate** (`sendShareGate`): Controls the permission to send shares.

Upon `withdraw`/`redeem` and `transfer`/`transferFrom`, `canSendShares` must return `true` for the shares sender if the gate is set.

This gate is critical because it can prevent people from withdrawing their shares, or prevent depositors from getting back their shares deposited on other contract.

**Receive Assets Gate** (`receiveAssetsGate`): Controls permissions related to receiving assets.

Upon `withdraw`/`redeem`, `canReceiveAssets` must return true for the `receiver` if the gate is set.

This gate is critical because it can prevent people from receiving their assets upon withdrawals.

**Send Assets Gate** (`sendAssetsGate`): Controls permissions related to sending assets.

Upon `deposit`/`mint`, `canSendAssets` must return true for  `msg.sender` must pass the `canSendAssets` check.

### Roles

#### Owner

The owner's role is to set the curator and sentinels.
Only one address can have this role.

It can:

- Set the owner.
- Set the curator.
- Set sentinels.
- Set the name.
- Set the symbol.

#### Curator

The curator's role is to curate the vault, meaning setting risk limits, gates, allocators, fees.
Only one address can have this role.

Curator actions are timelockable, except decreaseAbsoluteCap and decreaseRelativeCap.
Once the timelock has passed, the action can be executed by anyone.

It can:

<a id="curator-timelocks"></a>

- [Timelockable] Increase absolute caps.
- Decrease absolute caps.
- [Timelockable] Increase relative caps.
- Decrease relative caps.
- [Timelockable] Set adapters.
- [Timelockable] Set allocators.
- [Timelockable] Increase timelocks.
- [Timelocked by the timelock being decreased] Decrease timelocks.
- [Timelockable] Set the `performanceFee`.
  The performance fee is capped at 50% of generated interest.
- [Timelockable] Set the `managementFee`.
  The management fee is capped at 5% of assets under management annually.
- [Timelockable] Set the `performanceFeeRecipient`.
- [Timelockable] Set the `managementFeeRecipient`.
  The timelock of increaseTimelock should be set to a safe value that gives time to detect mistakes (e.g. 1 day) after the vault has been created and initial timelocks have been set.

#### Allocator

The allocators' role is to handle the allocation of the liquidity (inside the caps set by the curator).
They are notably responsible for the vault's liquidity.
Multiple addresses can have this role.

It can:

- Allocate funds from the “idle market” to enabled markets.
- Deallocate funds from enabled markets to the “idle market”.
- Set the `liquidityAdapter` and the `liquidityData`.
- Set the `maxRate`.

#### Sentinel

Multiple addresses can have this role.

It can:

- Deallocate funds from enabled markets to the “idle market”.
- Decrease absolute caps.
- Decrease relative caps.
- Revoke timelocked actions.

## Getting started

### Package installation

Install [Foundry](https://book.getfoundry.sh/getting-started/installation).

### Run tests

Run `forge test`.

## License

Files in this repository are publicly available under license `GPL-2.0-or-later`, see [`LICENSE`](./LICENSE).
