# Vault v2

Morpho Vault v2 enables anyone to create [non-custodial](#non-custodial) vaults that allocate assets to any protocols, including but not limited to Morpho Market v1, Morpho Market v2, and Morpho Vaults v1.
Depositors of Morpho Vault v2 earn from the underlying protocols without having to actively manage the risk of their position.
Management of deposited assets is the responsibility of a set of different roles (owner, curator and allocators).
The active management of invested positions involves enabling and allocating liquidity to protocols.

[Morpho Vault v2](./src/VaultV2.sol) is [ERC-4626](https://eips.ethereum.org/EIPS/eip-4626) and [ERC-2612](https://eips.ethereum.org/EIPS/eip-2612) compliant.
The [VaultV2Factory](./src/VaultV2Factory.sol) deploys instances of Vaults v2.
All the contracts are immutable.

## Overview

### Adapters

Vaults can allocate assets to arbitrary protocols and markets via adapters.
The curator enables adapters to invest on behalf of the vault.
Because adapters hold positions in protocols where assets are allocated, they are susceptible to accrue rewards for those protocols.
To ensure that those rewards can be retrieved, each adapter has a skim function that can be called by the vault's owner.
Adapters for the following protocols are currently available:

- [Morpho Market v1](./src/adapters/MorphoMarketV1Adapter.sol);
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
Note that relative caps are "soft" because they are not checked on withdrawals (they only constrain new allocations).
The curator ensures the consistency of the id system by:

- setting caps for the ids according to an estimation of risk;
- setting adapters that return consistent ids.

The ids of Morpho v1 lending markets could be for example the tuple `(CollateralToken, LLTV, Oracle)` and `CollateralToken` alone.
A vault could be setup to enforce the following caps:

- `(stETH, 86%, Chainlink)`: 10M
- `(stETH, 86%, Redstone)`: 10M
- `(stETH)`: 15M

This would ensure that the vault never has more than 15M exposure to markets with stETH as collateral, and never more than 10M exposure to an individual market.

### Liquidity

The allocator is responsible for ensuring that users can withdraw their assets at anytime.
This is done by managing the available idle liquidity and an optional liquidity adapter.

When users withdraw assets, the idle assets are taken in priority.
If there is not enough idle liquidity, liquidity is taken from the liquidity adapter.
When defined, the liquidity adapter is also used to forward deposited funds.

A typical liquidity adapter would allow deposit/withdrawals to go through a very liquid Market v1.

<a id="non-custodial"></a>

### Non-custodial guarantees

Non-custodial guarantees come from [in-kind redemptions](#in-kind-redemptions) and [timelocks](#curator-timelocks).
These mechanisms allow users to withdraw their assets before any critical configuration change takes effect.

<a id="in-kind-redemptions"></a>

### In-kind redemptions with `forceDeallocate`

To guarantee exits even in the absence of assets immediately available for withdrawal, the permissionless `forceDeallocate` function allows anyone to move assets from an adapter to the vault's idle assets.

`forceDeallocate` provides a form of in-kind redemption: users can flashloan liquidity, supply it to an adapters' market, and withdraw the liquidity through `forceDeallocate` before repaying the flashloan.
This reduces their position in the vault and increases their position in the underlying market.

A penalty for using forceDeallocate can be set per adapter, of up to 2%.
This disincentivizes the manipulation of allocations, in particular of relative caps which are not checked on withdraw.
Note that the only friction to deallocating an adapter with a 0% penalty is the associated gas cost.

[Gated vaults](Gates) can circumvent the in-kind redemption mechanism by configuring an `exitGate`.

### Vault Interest Controller (Vic)

Vault v2 can allocate assets across many markets, especially when interacting with Morpho Markets v2.
Looping through all markets to compute the total assets is not realistic in the general case.
This differs from Vault v1, where total assets were automatically computed from the vault's underlying allocations.
As a result, in Vault v2, curators are responsible for monitoring the vault’s total assets and setting an appropriate interest rate.
The interest rate is set through the Vic, a contract responsible for returning the `interestPerSecond` used to accrue fees.
The rate returned by the Vic must be below `200% APR`.

The vault interest controller can typically be simple smart contract storing the `interestPerSecond`, whose value is regularly set by the curator.
For now only a Vic of this type is provided, the [ManualVic](./src/vic/ManualVic.sol), with the following added features:

- the interest per second can be set by the allocators and sentinels of the vault;
- the Vic has an additional internal notion of max interest per second, to ensure that the role of allocator can be given more safely.
  The curator controls this internal notion of max interest per second, while the sentinels are only able to decrease it to reduce the risk of having a rate too high.

### Bad debt realization

In contrast to Morpho Vaults v1.0, bad debt realization is not autonomously realized on the vault when it is realized on the underlying market.
It can be realized on the vault by anyone for an incentive (1% of the loss).
To prevent flashloan based manipulations, when a loss is realized on the vault, deposits are blocked for the rest of the transaction.

### Gates

Vaults v2 can use external gate contracts to control share transfer, vault asset deposit, and vault asset withdrawal.

If a gate is not set, its corresponding operations are not restricted.

Gate changes can be timelocked.
Using `abdicateSubmit`, a curator can commit to keeping the vault completely ungated, or, for instance, to only gate deposits and shares reception, but not withdrawals.

Three gates are defined:

**Shares Gate** (`shareGate`): Controls permissions related to sending and receiving shares.
Implements [ISharesGate](./src/interfaces/IGate.sol).

When set:

- Upon `deposit`, `mint` and transfers, the shares receiver must pass the `canReceiveShares` check. Performance and management fee recipients must also pass this check, otherwise their respective fee will be 0.
- Upon `withdraw`, `redeem` and transfers, the shares sender must pass the `canSendShares` check.

If the shares gate reverts upon `canReceiveShares` and there is a nonzero fee to be sent, `accrueInterest` will revert.

**Receive Assets Gate** (`receiveAssetsGate`): Controls permissions related to receiving assets.
Implements [IReceiveAssetsGate](./src/interfaces/IGate.sol).

- Upon `withdraw` and `redeem`, `receiver` must pass the `canReceiveAssets` check.

**Send Assets Gate** (`sendAssetsGate`): Controls permissions related to sending assets.
Implements [ISendAssetsGate](./src/interfaces/IGate.sol).

- Upon `deposit` and `mint`, `msg.sender` must pass the `canSendAssets` check.

An example gate is defined in [test/examples/GateExample.sol](./test/examples/GateExample.sol).

### Roles

**Owner**

Only one address can have this role.

It can:

- Set the owner.
- Set the curator.
- Set sentinels.

**Curator**

Only one address can have this role.

Some actions of the curator are timelockable (between 0 and 3 weeks, or infinite if the action has been frozen).
Once the timelock passed, the action can be executed by anyone.

It can:

<a id="curator-timelocks"></a>

- [Timelockable] Increase absolute caps.
- Decrease absolute caps.
- [Timelockable] Increase relative caps.
- Decrease relative caps.
- [Timelockable] Set the `vic`.
- [Timelockable] Set adapters.
- [Timelockable] Set allocators.
- Increase timelocks.
- [Timelocked 3 weeks] Decrease timelocks.
- [Timelockable] Set the `performanceFee`.
  The performance fee is capped at 50% of generated interest.
- [Timelockable] Set the `managementFee`.
  The management fee is capped at 5% of assets under management annually.
- [Timelockable] Set the `performanceFeeRecipient`.
- [Timelockable] Set the `managementFeeRecipient`.
- [Timelockable] Abdicate submitting of an action.
  The timelock on abdicate should be set to a high value (e.g. 3 weeks) after the vault has been created and initial abdications have been done, if any.

**Allocator**

Multiple addresses can have this role.

It can:

- Allocate funds from the “idle market” to enabled markets.
- Deallocate funds from enabled markets to the “idle market”.
- Set the `liquidityAdapter`.
- Set the `liquidityData`.

**Sentinel**

Multiple addresses can have this role.

It can:

- Deallocate funds from enabled markets to the “idle market”.
- Decrease absolute caps.
- Decrease relative caps.
- Revoke timelocked actions.

### Main differences with Vault v1

- Vault v2 can supply to arbitrary protocols, including, but not limited to, Morpho Market v1 and Morpho Market v2.
- The curator is responsible for setting the interest of the vault.
  This implies monitoring interests generated by the vault in order to set an interest that is in line with the profits generated by the vault.
- Caps on markets can be set with more granularity than in Vault v1.
- Curators can set relative caps, limiting the maximum relative exposure of the vault to arbitrary factors (e.g. collateral assets or oracle).
- The owner no longer inherits the other roles.
- Most management actions are done by the curator, not the owner.
- The `Guardian` role of Vault v1 has been replaced by a `Sentinel` role.
  The scope of the sentinel is slightly different than that of the guardian role.
- Timelocked actions are subject to configurable timelock durations, set individually for each action.
- Bad debt realization is not automatic, but any allocation or deallocation will realize bad debt amounts returned by the adapter.

## Getting started

### Package installation

Install [Foundry](https://book.getfoundry.sh/getting-started/installation).

### Run tests

Run `forge test`.

## License

Files in this repository are publicly available under license `GPL-2.0-or-later`, see [`LICENSE`](./LICENSE).
