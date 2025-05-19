# Vault v2

Morpho Vault V2 enables anyone to create vaults that allocate assets to any protocols, including but not limited to Morpho Market V1, Morpho Market V2, and ERC-4626 strategies.
Depositors of Morpho Vault V2 earn from the underlying protocols without having to actively manage the risk of their position.
Management of deposited assets is the responsability of a set of different roles (owner, curator and allocators).
The active management of invested positions involve enabling and allocating liquidity to protocols.

[Morpho Vault V2](./src/VaultV2.sol) shares are [ERC-20](https://eips.ethereum.org/EIPS/eip-20) compliant, with [ERC-2612](https://eips.ethereum.org/EIPS/eip-2612) permit.
The [VaultV2Factory](./src/VaultV2Factory.sol) deploys instances of Vaults V2.
All the contracts are immutable.

## Overview

### Curation

Vaults can allocate assets not only to Morpho Markets V1 and V2, but also to external protocols, such as ERC-4626 vaults.
The funds allocation of the vault is constrained by an id system.
An id is an abstract identifier of a common risk factor of some markets (a collateral, an oracle, a protocol, etc.).
The allocation on markets with a common id is limited by absolute caps and relative caps that can be set by the curator.
Note that relative caps are "soft" because they are not checked on withdrawals (they only constrain new allocations).
The curator enables adapters to invest on behalf of the vault.
They are notably trusted to return the ids associated with a given market.

Adapters for the following protocols are currently available:

- [Morpho Market V1](./src/adapters/MorphoBlueAdapter.sol)
- [ERC-4626](./src/adapters/ERC4626Adapter.sol)

A Morpho Market V2 adapter will be released together with Market V2.

The ids of Morpho V1 lending markets could be for example the tuple `(CollateralToken, LLTV, Oracle)` and `CollateralToken` alone.
A vault could be setup to enforce the following caps:

- `(stETH, 86%, Chainlink)`: 10M
- `(stETH, 86%, Redstone)`: 10M
- `(stETH)`: 15M

This would ensure that the vault never have more than 15M exposure to markets with stETH as collateral, and never more than 10M exposure to an individual market.

### Liquidity

The allocator is responsible for ensuring that users can withdraw their assets at anytime.
This is done by managing the available liquidity in `idle` and in an optional liquidity market $M$.

As for other protocols, the liquidity market is defined using an adapter (`liquidityAdapter`).
When users withdraw assets, the assets are taken in priority from the `idle` market.
If the `idle` market does not have enough liquidity, liquidity is taken from the liquidity market $M$.
When defined, the liquidity market $M$ is also used as the market users are depositing into when supplying to the vault.

The market $M$ would typically be a very liquid Market V1.

### Vault Interest Controller

Vault V2 can allocate assets across many markets, especially when interacting with Morpho Markets V2.
Looping through all markets to compute the total assets is not realistic in the general case.
This differs from Vault V1, where total assets were automatically computed from the vault's underlying allocations.
As a result, in Vault V2, curators are responsible for monitoring the vault’s total assets and setting an appropriate interest rate.
The interest rate is set through the VIC, a contract responsible for returning the `interestPerSecond` used to accrue fees.

The vault interest controller can typically be simple smart contract storing the `interestPerSecond`, whose value is regularly set by the curator.
The rate returned by the VIC must be below `200% APR`.

### Bad debt

Similarly, the curator is responsible for monitoring the vault's bad debt.
In contrast to Vault V1.0, bad debt realization is not atomic to avoid share price manipulation with flash loans.

### Roles

**Owner**

Only one address can have this role.

It can:

- Set the owner.
- Set the curator.
- Set sentinels.

**Curator**

Only one address can have this role.

Some actions of the curator are timelockable (between 0 and 2 weeks, or infinite if the action has been frozen).
Once the timelock passed, the action can be executed by anyone.

It can:

- [Timelockable] Increase absolute caps.
- Decrease absolute caps.
- [Timelockable] Increase relative caps.
- Decrease relative caps.
- [Timelockable] Set the `vic`.
- [Timelockable] Set adapters.
- [Timelockable] Set allocators.
- Increase timelocks.
- [Timelocked 2 weeks] Decrease timelocks.
- [Timelockable] Set the `performanceFee`.
  The performance fee is capped at 50% of generated interest.
- [Timelockable] Set the `managementFee`.
  The management fee is capped at 5% of assets under management annually.
- [Timelockable] Set the `performanceFeeRecipient`.
- [Timelockable] Set the `managementFeeRecipient`.
- [Timelockable] Abdicate submitting of an action.
  This should be set to a high value (e.g. 2 weeks) after the vault has been created and some abdications have been done, if any.

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

### Main differences with Vault V1

- Vault V2 can supply to arbitrary protocols, including, but not limited to, Morpho Market V1 and Morpho Market V2.
- The curator is responsible for setting the interest of the vault.
  This implies monitoring interests generated by the vault in order to set an interest that is in line with the profits generated by the vault.
- Caps on markets can be set with more granularity than in Vault V1.
- Curators can set relative caps, limiting the maximum relative exposure of the vault to arbitrary factors (e.g. colaterral assets or oracle).
- The owner no longer inherits the other roles.
- Most management actions are done by the curator, not the owner.
- The `Guardian` role of Vault V1 has been replaced by a `Sentinel` role.
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
