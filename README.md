# Vault v2

Morpho Vault V2 enables anyone to create vaults that allocate assets to any protocols, including but not limited to Morpho Market V1, Morpho Market V2, and ERC-4626 strategies.
Depositors of Morpho Vault V2 earn from the underlying protocols without having to actively manage the risk of their position.
Management of deposited assets is the responsability of a set of different roles (owner, curator and allocators).
The active management of invested positions involve enabling and allocating liquidity to protocols.

[Morpho Vault V2](https://github.com/morpho-org/vaults-v2/blob/main/src/VaultV2.sol) vaults are [ERC-4626](https://eips.ethereum.org/EIPS/eip-4626) compliant, with [ERC-2612](https://eips.ethereum.org/EIPS/eip-2612) permit.
A given Morpho Vault V2 has one unique deposit asset.
The [VaultV2Factory](https://github.com/morpho-org/vaults-v2/blob/main/src/VaultV2Factory.sol) deploys instances of Vaults V2.
All the contracts are immutable.

## Overview

### Adapters

Vault V1 strategies were defined by a tuple of the form `(CollateralToken, LoanToken, LLTV, Oracle, IRM)`,
which defined offers accepted by the vault.
Vault V2 introduces more flexibility in defining strategies.
Vaults can allocate assets not only to Morpho Markets V1 and V2,
but also to external protocols, such as ERC-4626 vaults.
Curators enable protocols in which the vault can supply through the use of adapters.

In order to enable a given protocol, a corresponding adapter need to be used.
Adapters for the following protocols are currently available:
- [Morpho Market V1](./src/adapters/MorphoAdapter.sol)
- [ERC-4626](./src/adapters/ERC4626Adapter.sol)

A Morpho Market V2 adapter will be released together with Market V2.
Additional adapters can be developed to support other protocols as needed.

When supplying through an adapter, the adapter returns arbitrary bytes32 identifiers (IDs).
Those IDs can be thought as some properties of the protocol the adapter supply to,
such as the collateral asset or the oracle in the case of a lending market.
The vault tracks assets allocation across the different IDs.
Absolute caps and relative caps can be set by the curator for each of the IDs.
Upon allocation in a market, the allocation is increased and caps are checked.
Upon deallocation from a market, the allocation is decreased without checks.
On withdrawals from the vault, the relative caps are checked.
The vault does not enforce any structure or semantics on IDs.

IDs of lending markets for a given `LoanToken` can be defined using a tuple of the form `(CollateralToken, LLTV, Oracle)`.
A vault could be setup to enforce the following caps:
- `(stETH, *, Chainlink)`: 6M
- `(stETH, *, Redstone)`: 6M
- `(stETH, *, *)`: 10M

This would ensure that the vault never have more than 10M exposure to the stETH asset,
and never more than 6M exposure to markets using chainlink or redstone oracles, for any LLTV.

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
In contrast to Vault V1.0, bad debt realisation is not atomic to avoid share price manipulation with flash loans.

### Roles

**Owner**

Only one address can have this role.

It can:

- Set the owner.
- Set the curator.
- Set sentinels.

**Curator**

Only one address can have this role.

Some actions of the curator are timelockable (between 0 and 2 weeks).
Once the timelock passed, the action can be executed by anyone.

It can:

- [Timelockable] Increase absolute caps.
- Decrease absolute caps.
- [Timelockable] Increase relative caps.
- [Timelockable] Decrease relative caps.
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

- Allocate funds from enabled markets to the “idle market”.
- Decrease absolute caps.
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
- Bad debt should be monitored and realised by the curator and bad debt realisation is not atomic.

## Getting started

### Package installation

Install [Foundry](https://book.getfoundry.sh/getting-started/installation).

### Run tests

Run `forge test`.

## Audits

All audits are stored in the [`audits`](./audits) folder.

## License

Files in this repository are publicly available under license `GPL-2.0-or-later`, see [`LICENSE`](./LICENSE).
