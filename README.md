# Vault v2

Morpho Vault V2 is a protocol for noncustodial risk management.
It enables anyone to create a vault depositing liquidity into different venues, including Morpho markets V1 and V2.

Users of Morpho Vault V2 are liquidity providers who want to earn from borrowing interest without having to actively manage the risk of their position.
The active management of the deposited assets is the responsibility of a set of different roles.
These roles are primarily responsible for enabling and disabling markets on Morpho Market V1 and Morpho Market V2 as well as managing the allocation of users’ funds across those markets.

[Morpho Vault V2](https://github.com/morpho-org/vaults-v2/blob/main/src/VaultV2.sol) vaults are [**ERC-4626](https://eips.ethereum.org/EIPS/eip-4626)** vaults, with ([ERC-2612](https://eips.ethereum.org/EIPS/eip-2612)) permit.
One Morpho Vault V2 is related to one loan asset.
The [VaultV2Factory](https://github.com/morpho-org/vaults-v2/blob/main/src/VaultV2Factory.sol) is deploying immutable onchain instances of Vaults V2.

## Overview

There are 5 different roles for a MetaMorpho vault: owner, curator, sentinel, treasurer and allocator.

The owner is responsible for defining the markets that the vault will lend against by setting adapters.
The curator and allocator are then responsible for the management of the corresponding markets by setting caps and allocation of funds across those markets.

Each market has a supply cap and a relative cap that guarantees lenders both a maximum absolute and a maximum relative exposure to the specific market.
Users can supply or withdraw assets at any time, depending on the available liquidity on the liquidity market.

In Vault V2, all actions can be timelocked (except `reallocateIn` and `reallocateOut`).
Owners are encouraged to subject actions that may be against users' interests (e.g. enabling a market with a high exposure) to a timelock.
Timelocks change must set the value between 0 and 2 weeks.

The `sentinel`, if set, can revoke the actions taken by other roles during the timelock, with the exception of the action setting the sentinel.
After the timelock, actions can be executed by anyone.

### Adapters and markets in Vault V2

In Vault V1, markets were defined by a tuple of the form `(CollateralAsset, LoanAsset, LLTV, Oracle, IRMAddress)`.
Vault V2 allow for more flexibility in defining offers accepted by the vault.

Markets V2 for a given `LoanAsset` are defined using a tuple of the form `(CollateralAsset, LLTV, Oracle)`,
where each value of the triplet can correspond to multiple values (including all possible values).
For instance, a market defined by the following triplet `(wstETH/WETH, 94.5%, .)` would accept borrowing offers on the pair
`wstETH/WETH` with an LLTV of `94,5%` using any oracle.
In practice, markets that the vault will lend against are defined by the owner of the vault, by setting adapters.
Adapters enable vaults to track and control exposure to given markets through maximum and relative caps.

While adapters have been designed in the context of Morpho Markets V2, they are more general and can be used to supply liquidity to other protocols.

### Liquidity market

The allocator is responsible for ensuring that users can withdraw their assets at anytime.
This is done by managing the available liquidity in the `idle` and an optional liquidity market $M$.

When users withdraw assets, the assets are taken in priority from the `idle` market.
If the `idle` market does not have enough liquidity, the market $M$ is used.
When defined, the market $M$ is also used as the market users are depositing into.

The market $M$ should typically be a very liquid Market V1.

### Interest Rate Model (IRM)

The IRM is responsible for returning the `interestPerSecond` that is used when accruing fees.

The IRM can typically be simple smart contract storing the  `interestPerSecond`, whose value is regularly set by the curator.
The rate returned by the IRM must be below `200% APR`.
This model is in contrast with Vault V1 were the interest was automatically computed from the underlying allocations.
This entails monitoring the vault's interest accrual in order to set a reasonable interest.

### Roles

**Owner**

Only one address can have this role.

It can:

- Set other roles:
    - `sentinel`
    - `owner`
    - `curator`
    - `treasurer`
    - `allocator`
- Set the `performanceFeeRecipient`.
- Set the `managementFeeRecipient`.
- Set the `irm`. The `irm` is responsible for returning the per second interests accrued by users. This is in contrast with Vault V1 where the interest was automatically computed based on the underlying allocations.
- [Timelocked] Set adapter.
- [Timelocked] Increase the timelock.
- [Timelocked] Decrease the timelock.

**Treasurer**

Only one address can have this role.

It can:

- Set the `performanceFee`. The performance fee is capped at 50% of generated interest.
- Set the `managementFee`. The management fee is capped at 5% of generated interest.

**Allocator**

Multiple addresses can have this role.

It can:

- Reallocate funds from the “idle market” to enabled markets.
- Reallocate funds from enabled markets to the “idle market”.

**Curator**

Only one address can have this role.

It can:

- [Timelocked] Decrease the absolute supply cap of any market.
- [Timelocked] Decrease the relative supply cap of any market.
- [Timelocked] Increase the absolute supply cap of any market.
- [Timelocked] Increase the relative supply cap of any market.

**Sentinel**

Multiple addresses can have this role.

It can:

- Reallocate funds from the “idle market” to enabled markets.
- Reallocate funds from enabled markets to the “idle market”.
- [Timelocked] Decrease the absolute supply cap of any market.
- Revoke actions from other roles, except the `setSentinel` action (contrary to Vault V1, the sentinel cannot revoke any attempt to change the sentinel).

### Main differences with Vault V1

- The curator is responsible for setting the interest of the vault. This implies monitoring interests generated by the vault in order to set an interest that is in line with the profits generated by the vault.
- Contrary to Vault V1, the `Owner` does not inherit the other roles.
- The `Guardian` role of Vault V1 has been replaced by a `Sentinel` role. The scope of the sentinel is slightly different than that of the guardian role.
- The `Treasurer` role has been introduced. This role can set the performance and management fees. Separating the treasurer role from the curator opens the possibility of managing the fees more dynamically.
- All actions are timelockable, except `reallocateIn` and `reallocateOut` and timelocks are not constrained anymore.

## Getting started

### Package installation

Install [Foundry](https://book.getfoundry.sh/getting-started/installation).

### Run tests

Run `forge test`.

## Audits

All audits are stored in the [`audits`](./audits) folder.

## License

Files in this repository are publicly available under license `GPL-2.0-or-later`, see [`LICENSE`](./LICENSE).
