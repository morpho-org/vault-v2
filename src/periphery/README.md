# Periphery

Peripheral, non-core contracts that build on top of Vault V2.

## Blue Public Allocator

`BluePublicAllocator` lets anyone (not only the vault's allocators) reallocate a Vault V2's liquidity between Morpho Blue markets reached through the `MorphoMarketV1AdapterV2`, within limits set by the vault's roles.

To be usable, it must be set as an allocator of the vault.

It inherits the vault's roles:

- the vault's allocators set active adapters, the per-market absolute cap, `canDeallocate` and `canAllocateFromIdle`;
- the vault's allocators set and claim the native-currency penalty charged on each `reallocate` / `allocateFromIdle` call.

The vault's own caps are still enforced, so an allocation reverts if it would exceed them. Because anyone can move liquidity, the contract opens the door to manipulating relative caps through short-term deposits (this requires capital).
