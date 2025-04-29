# Vault v2

Morpho Vault V2 enables anyone to create vaults in which users may deposit liquidity for vault operators to invest in different venues including, but not limited to, Morpho markets.

Depositors of Morpho Vault V2 earn from borrowing interest without having to actively manage the risk of their position.
The active management of the deposited assets is the responsibility of a set of different roles.
These roles are primarily responsible for enabling and disabling markets on Morpho Market V1 and Morpho Market V2 as well as managing the allocation of users’ funds across those markets.

[Morpho Vault V2](https://github.com/morpho-org/vaults-v2/blob/main/src/VaultV2.sol) vaults are [ERC-4626](https://eips.ethereum.org/EIPS/eip-4626) compliant, with [ERC-2612](https://eips.ethereum.org/EIPS/eip-2612) permit.
A given Morpho Vault V2 has one unique underlying asset.
The [VaultV2Factory](https://github.com/morpho-org/vaults-v2/blob/main/src/VaultV2Factory.sol) deploys instances of Vaults V2.
All the contracts are immutable.

## Overview

There are 5 different roles for a Morpho vault V2: owner, curator, sentinel, treasurer and allocator.

Each market has an absolute cap and a relative cap that guarantees lenders both a maximum absolute and a maximum relative exposure to the specific market.
Users can supply or withdraw assets at any time, depending on the available liquidity on the liquidity market.

In Vault V2, all permissioned actions can be timelocked (except `reallocateIn` and `reallocateOut`).
Owners are encouraged to subject actions that may be against users' interests (e.g. enabling a market) to a timelock.
Timelocks values must be between 0 and 2 weeks.

Sentinels can revoke the actions taken by other roles during the timelock, with the exception of the action of setting and unsetting a sentinel.
After the timelock, actions can be executed by anyone.

### Adapters

Vault V1 strategies were defined by a tuple of the form `(CollateralToken, LoanToken, LLTV, Oracle, IRMAddress)`,
which defined offers accepted by the vault.
Vault V2 introduces more flexibility in defining strategies.
Vaults can allocate assets not only to Morpho Markets V1 and V2,
but also to external protocols, such as ERC-4626 vaults.
Curators enable protocols in which the vault can supply through the use of adapters.

In order to enable a given protocol, a corresponding adapter need to be used.
Adapters for the following protocols are available:
- Morpho Market V1
- Morpho Market V2
- ERC-4626

When supplying through an adapter, the adapter returns arbitrary bytes32 identifiers (IDs).
Those IDs can be thought as some properties of the protocol the adapter supply to,
such as the collateral asset or the oracle in the case of a lending market.
For each ID, the vault tracks an absolute cap and an allocation.
On supply, the allocation is increased and the cap is checked.
On withdrawal, the allocation is decreased without checks.
The vault does not enforce any structure or semantics on IDs.

IDs of lending markets for a given `LoanToken` can be defined using a tuple of the form `(CollateralToken, LLTV, Oracle)`.
A vault could be setup to enforce the following caps:
- `(stETH, *, Chainlink)`: 6M
- `(stETH, *, Redstone)`: 6M
- `(stETH, *, *)`: 10M

This would ensure that the vault never have more than 10M exposure to the stETH asset,
and never more than 6M exposure to markets using chainlink or redstone oracles, for any LLTV.

### Liquidity market

The allocator is responsible for ensuring that users can withdraw their assets at anytime.
This is done by managing the available liquidity in `idle` and in an optional liquidity market $M$.

When users withdraw assets, the assets are taken in priority from the `idle` market.
If the `idle` market does not have enough liquidity, the market $M$ is used.
When defined, the market $M$ is also used as the market users are depositing into.

The market $M$ would typically be a very liquid Market V1.

### Interest Rate Model (IRM)

Vault V2 can allocate assets across many markets, especially when interacting with Morpho Markets V2.
Looping through all markets to compute the total assets is not realistic in the general case.
This differs from Vault V1, where total assets were automatically computed from the vault's underlying allocations.
As a result, in Vault V2, curators are responsible for monitoring the vault’s total assets and setting an appropriate interest rate.
The interest rate is set through the IRM, a contract responsible for returning the `interestPerSecond` used to accrue fees.

The IRM can typically be simple smart contract storing the `interestPerSecond`, whose value is regularly set by the curator.
The rate returned by the IRM must be below `200% APR`.

### Bad debt

Similarly, the curator is responsible for monitoring the vault's bad debt.
In contrast to Vault V1.0, bad debt realisation is not atomic to avoid share price manipulation with flash loans.

### Roles

**Owner**

Only one address can have this role.

It can:

- [Timelocked] Set other roles:
  - `sentinel`
  - `owner`
  - `curator`
  - `treasurer`
  - `allocator`
- [Timelocked] Set the `performanceFeeRecipient`.
- [Timelocked] Set the `managementFeeRecipient`.
- [Timelocked] Set the `irm`.
- [Timelocked] Set adapter.
- [Timelocked] Increase the timelock.
- [Timelocked] Decrease the timelock.

**Treasurer**

Only one address can have this role.

It can:

- [Timelocked] Set the `performanceFee`.
  The performance fee is capped at 50% of generated interest.
- [Timelocked] Set the `managementFee`.
  The management fee is capped at 5% of assets under management annually.

**Allocator**

Multiple addresses can have this role.

It can:

- Reallocate funds from the “idle market” to enabled markets.
- Reallocate funds from enabled markets to the “idle market”.

**Curator**

Only one address can have this role.

It can:

- [Timelocked] Change the absolute supply cap of any market.
- [Timelocked] Change the relative supply cap of any market.

**Sentinel**

Multiple addresses can have this role.

It can:

- Reallocate funds from the “idle market” to enabled markets.
- Reallocate funds from enabled markets to the “idle market”.
- [Timelocked] Decrease the absolute supply cap of any market.
- Revoke actions from other roles, except the `setSentinel` action (contrary to Vault V1, the sentinel cannot revoke any attempt to change the sentinel).

### Main differences with Vault V1

- Vault V2 can supply to arbitrary protocols, including, but not limited to, Morpho Market V1 and Morpho Market V2.
- The curator is responsible for setting the interest of the vault.
  This implies monitoring interests generated by the vault in order to set an interest that is in line with the profits generated by the vault.
- Contrary to Vault V1, the `Owner` does not inherit the other roles.
- The `Guardian` role of Vault V1 has been replaced by a `Sentinel` role.
  The scope of the sentinel is slightly different than that of the guardian role.
- The `Treasurer` role has been introduced.
  This role can set the performance and management fees.
  Separating the treasurer role from the curator opens the possibility of managing the fees more dynamically.
- All actions can have a specific timelock (except `reallocateIn` and `reallocateOut`) and timelocks are not constrained anymore.
- Bad debt should be monitored by the curator and bad debt realisation is not atomic.

## Getting started

### Package installation

Install [Foundry](https://book.getfoundry.sh/getting-started/installation).

### Run tests

Run `forge test`.

## Audits

All audits are stored in the [`audits`](./audits) folder.

## License

Files in this repository are publicly available under license `GPL-2.0-or-later`, see [`LICENSE`](./LICENSE).
