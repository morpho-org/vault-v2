# Periphery

Peripheral, non-core contracts that build on top of Vault V2.
Blue public allocator contracts are in [blue-public-allocator](./blue-public-allocator/).
Gate contracts are in [gates](./gates/).
Adapter registry contracts are in [registries](./registries/).

## Blue Public Allocator

`BluePublicAllocator` lets anyone (not only the vault's allocators) reallocate a Vault V2's liquidity between Morpho Blue markets reached through the `MorphoMarketV1AdapterV2`, within the vault's caps, and the public allocator's own limits.
Vault allocators configure which adapters are active, which markets can be deallocated from, each market's absolute cap, and whether idle assets can be allocated publicly.
Public callers must pay the vault's native penalty on each `reallocate` or `allocateFromIdle` call.

## Whitelist Receive Shares Gate

`WhitelistReceiveSharesGate` is an implementation of the vault's `receiveSharesGate`.
It restricts who can receive vault shares, including shares minted on deposits/mints and shares received by transfer.
A whitelisted account can still hold shares on behalf of non-whitelisted accounts, so this gate does not fully restrict who can access the vault's payoff.
If an account transfers shares to another account, for example into another protocol, it may be unable to receive them back if that account is not whitelisted later.

## Whitelist Send Assets Gate

`WhitelistSendAssetsGate` is an implementation of the vault's `sendAssetsGate`.
It restricts who can send assets into the vault on deposits and mints.
Whitelisted accounts can still deposit assets that originally belong to non-whitelisted accounts, so this gate does not fully restrict whose funds can enter the vault.

## Registries

Adapter registries implement the vault's `IAdapterRegistry` interface (`isInRegistry(address)`) so a vault can validate the adapters it uses.
`RegistryList` is an owner-controlled, append-only list of sub-registries; an adapter is in the registry if it is in any sub-registry.
`MorphoMarketV1RegistryV2` validates adapters created by the `MorphoMarketV1AdapterV2Factory`.
`MorphoVaultV1Registry` validates adapters created by the `MorphoVaultV1AdapterFactory` whose underlying MetaMorpho vault was created by the MetaMorpho factory.
