# Vault V2

> [!NOTE]
> Vault V2 instances are distinguished between:
> - **Morpho Vaults**: Vault V2 with the Morpho registry (link to be added) abdicated. Learn more about Morpho Vaults and their benefits here (link to be added).
> - **Basic Vaults**: Vault V2 that can supply to any protocol. They don't get all the Morpho Vaults benefits. In particular, Vault V2 has been developed and audited only in the context of the Morpho Market V1 and Morpho Vault V1 adapters.

Vault V2 enables anyone to create [non-custodial](#non-custodial-guarantees) vaults that allocate assets to any protocols, including Morpho Market V1, Morpho Market V2, and Morpho Vault V1.
Depositors of Vault V2 earn from the underlying protocols without having to actively manage their position.
Management of deposited assets is the responsibility of a set of different roles (owner, curator and allocators).

[Vault V2](./src/VaultV2.sol) is [ERC-4626](https://eips.ethereum.org/EIPS/eip-4626) and [ERC-2612](https://eips.ethereum.org/EIPS/eip-2612) compliant.
The [VaultV2Factory](./src/VaultV2Factory.sol) deploys instances of Vaults V2.
All the contracts are immutable.

## Overview

### Adapters

Vaults can allocate assets to arbitrary protocols and markets via separate contracts called adapters.
They hold positions on behalf of the vault.
Adapters are also used to know how much these investments are worth (interest and loss realization).

Vaults can set an adapter registry to constrain which adapter they can have and add. This is notably useful when abdicated (see [timelocks](#timelocks)), to ensure that a vault will forever supply into adapters authorized by a given registry. See for example the Morpho Registry (link to be added).

The following adapters are currently available:
- [Morpho Market V1 Adapter](./src/adapters/MorphoMarketV1Adapter.sol).
  This adapter allocates to any Morpho Market V1, under the constraints of the [caps](#caps).
- [Morpho Vault V1 Adapter](./src/adapters/MorphoVaultV1Adapter.sol).
  This adapter allocates to a fixed Morpho Vault V1 (V1.0 and V1.1), under the constraints of the [caps](#caps).
  Note that using this adapter with vaults other than Morpho Vaults V1 has not been audited.
- Morpho Market V2 Adapter. WIP

### Caps

The funds allocation of the vault is constrained by an id-based caps system.
An id is an abstract identifier for a common risk factor of some markets (a collateral, an oracle, a protocol, etc.).
Allocation on markets with a common id is limited by absolute caps and relative caps.
Note that relative caps are "soft" because they are not checked on withdrawals, they only constrain new allocations.

### Liquidity

The allocator is responsible for ensuring that users can withdraw their assets at any time.
This is done by managing the available idle liquidity and an optional liquidity adapter.

When users withdraw assets, the idle assets are taken in priority.
If there is not enough idle liquidity, liquidity is taken from the liquidity adapter.
When defined, the liquidity adapter is also used to forward deposited funds.

A typical liquidity adapter would allow deposits/withdrawals to go through a very liquid Market V1.

### Timelocks

Curator configuration changes are all timelockable (except `decreaseAbsoluteCap` and `decreaseRelativeCap`), meaning that doing an action requires submitting it first, and only when the timelock has passed it can be executed (by anyone).
This is useful notably to the [non-custodial guarantees](#non-custodial-guarantees), but also in general if a curator wants to give guarantees about some configurations.
`increaseTimelock` should be used carefully, because decreaseTimelock is function-dependent: decreasing the timelock of a function is timelocked by the timelock of the function itself.

Also, a configuration can be *abdicated*, meaning that it won't be able to be set anymore, by calling `abdicate`.

### In-kind redemptions

To guarantee exits even in the absence of assets immediately available for withdrawal, the permissionless `forceDeallocate` function allows anyone to move assets from an adapter to the vault's idle assets (meaning the vault token balance).

Users can redeem in-kind thanks to the `forceDeallocate` function: flashloan liquidity, supply it to an adapter's market, and withdraw the liquidity through `forceDeallocate` before repaying the flashloan.
This reduces their position in the vault and increases their position in the underlying market.

A penalty for using forceDeallocate can be set per adapter, of up to 2%.
This disincentivizes the manipulation of allocations, in particular of relative caps which are not checked on withdrawals.
Note that the only friction to deallocating an adapter with a 0% penalty is the associated gas cost.

### Non-custodial guarantees

Non-custodial guarantees come from [in-kind redemptions](#in-kind-redemptions-with-forcedeallocate) and [timelocks](#curator-timelocks).
These mechanisms ensure users that they can always withdraw their assets before any critical configuration change takes effect (if the right timelocks are not zero).

### Gates

Vaults V2 can use external gate contracts to control share transfer, vault asset deposit, and vault asset withdrawal.
If a gate is not set, its corresponding operations are not restricted.

Four gates are defined:

- **Receive shares gate** (`receiveSharesGate`): Controls the permission to receive shares.
- **Send shares gate** (`sendSharesGate`): Controls the permission to send shares.
- **Receive assets Gate** (`receiveAssetsGate`): Controls permissions related to receiving assets.
- **Send assets Gate** (`sendAssetsGate`): Controls permissions related to sending assets.

### Max rate

The vault's share price will not increase faster than the allocator-set `maxRate`.
This can be useful to stabilize the distributed rate, or build a buffer to be able to absorb losses.

### Fees

VaultV2 depositors are charged with a performance fee, which is a cut on interest (capped at 50%), and a management fee (capped at 5%/year), which is a cut on principal.
Each fee goes to its respective recipient set by the curator.

### Roles

- **Owner**: The owner's role is to set the curator and sentinels.
It can also set the name and symbol of the vault.
Only one address can have this role.

- **Curator**: The curator's role is to configure the vault.
They can enable and disable [adapters](#adapters) and an optional adapter registry, configure [risk limits](#caps) by setting absolute and relative caps, set the [gates](#gates), the [allocators](#allocators), the [timelocks](#timelocks), the [fees](#fees) and the fee recipients.
All actions are timelockable except decreasing absolute and relative caps.
Only one address can have this role.

- **Allocator(s)**: The allocators' role is to handle the vault's allocation in and out of underlying protocols (with the enabled adapters, and within the caps set by the curator).
  They also set the [liquidity adapter](#liquidity) and [max rate](#max-rate).
They are notably responsible for the vault's performance and liquidity.

- **Sentinel(s)**: The sentinel role can be used to be able to derisk quickly a vault.
They are able to revoke pending actions, deallocate funds to idle and decrease caps.

## Developers

Compilation, testing and formatting with [forge](https://book.getfoundry.sh/getting-started/installation).

## Audits

All audits are stored in the [audits](./audits/)' folder.

## License

Files in this repository are publicly available under license `GPL-2.0-or-later`, see [`LICENSE`](./LICENSE).
