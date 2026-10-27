# Periphery

Peripheral, non-core contracts that build on top of Vault V2.
Blue public allocator contracts are in [blue-public-allocator](./blue-public-allocator/).
Gate contracts are in [gates](./gates/).
Adapter registry contracts are in [registries](./registries/).

## Blue Public Allocator

`BluePublicAllocator` lets anyone (not only the vault's allocators) reallocate a Vault V2's liquidity between Morpho Blue markets reached through the `MorphoMarketV1AdapterV2`, within the vault's caps, and the public allocator's own limits.
Vault allocators configure which adapters are active, which markets can be pulled from, each market's absolute cap, and whether idle assets can be pulled from publicly.
Public callers must pay the vault's penalty on each `reallocate` or `allocateFromIdle` call, a proportion of the assets moved, paid in the market's loan token and sent directly to the vault (a donation).

## Vault V2 Gates

Vault V2 calls these gates to check transfers of vault shares or assets.
They are configured on the vault, not on a Midnight market.

### Whitelist Receive Shares Gate

`WhitelistReceiveSharesGate` is an implementation of the vault's `receiveSharesGate`.
It restricts who can receive vault shares, including shares minted on deposits/mints and shares received by transfer.
A whitelisted account can still hold shares on behalf of non-whitelisted accounts, so this gate does not fully restrict who can access the vault's payoff.
If an account transfers shares to another account, for example into another protocol, it may be unable to receive them back if that account is not whitelisted later.

### Whitelist Send Assets Gate

`WhitelistSendAssetsGate` is an implementation of the vault's `sendAssetsGate`.
It restricts who can send assets into the vault on deposits and mints.
Whitelisted accounts can still deposit assets that originally belong to non-whitelisted accounts, so this gate does not fully restrict whose funds can enter the vault.

## Midnight Enter Gates and Subgates

These contracts control increases in credit or debt in Midnight markets, not transfers of vault shares or assets.
Midnight calls the gate at `Market.enterGate`. That gate can call a subgate to check permissions.

### `VaultV2CompatibleEnterGate`

Despite its name, this is a Midnight enter gate, not a Vault V2 gate.
Midnight calls its `canIncreaseCredit(account)` and `canIncreaseDebt(account)` functions.
One gate can serve multiple markets on one Midnight.
For ordinary permission checks, the gate calls its `subGate` with the account.
During `forceDeallocate`, a Midnight adapter from a registered factory can temporarily admit a shareholder of its parent vault to receive credit without subgate approval. The adapter sells through its own offer, without callback, and clears the admission as soon as its sale returns.
The gate checks the selling adapter's liquidation lock to prevent buyer callbacks from reusing admission.

### `VaultV2CompatibleEnterGateFactory`

Deploys `VaultV2CompatibleEnterGate` contracts using `CREATE2`.
The factory records each gate in `isCreated[gate]` and indexes it by subgate, Midnight and salt in `vaultV2CompatibleEnterGate`.

### `WhitelistEnterSubGate`

A subgate that restricts which accounts can increase their credit or debt in the markets of the gates that use it.
`VaultV2CompatibleEnterGate` calls this subgate with an account.
It cannot be used directly as a Midnight or Vault V2 gate.

Each side (credit, debt) has one whitelist for all markets: only whitelisted accounts can enter on that side.
Each side has its own role setter, who grants or revokes the whitelister role on that side.
Whitelisters edit the lists directly with `setIsWhitelisted` or allow to edit the list by EIP-712 signatures used by `setIsWhitelistedWithSig`.
`setIsWhitelistedWithSig` accepts a stale nonce when the account is already set to the signed value. The signature must still be unexpired and from a current whitelister.
A side can be made open at deployment, letting any account enter on that side (forever).

### `WhitelistEnterSubGateFactory`

Deploys a deterministic `WhitelistEnterSubGate` using `CREATE2` with a salt derived from the caller and a caller-provided pre-salt.
The factory records subgates in `isCreated`.

## Registries

Adapter registries implement the vault's `IAdapterRegistry` interface (`isInRegistry(address)`) so a vault can validate the adapters it uses.
`RegistryList` is an owner-controlled, append-only list of sub-registries; an adapter is in the registry if it is in any sub-registry.
`MorphoMarketV1RegistryV2` validates adapters created by the `MorphoMarketV1AdapterV2Factory`.
`MorphoVaultV1Registry` validates adapters created by the `MorphoVaultV1AdapterFactory` whose underlying MetaMorpho vault was created by the MetaMorpho factory.
