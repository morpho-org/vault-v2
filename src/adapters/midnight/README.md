# Midnight Adapter

Midnight Adapter. WIP.

## In-kind redemptions

With the Midnight adapter, the user instead buys the adapter's credit through `forceDeallocate`, at face value plus Midnight's settlement fee, then withdraws from the vault and repays the flashloan.

## Midnight Enter Gates and Subgates

These contracts control increases in credit or debt in Midnight markets, not transfers of vault shares or assets.
Midnight calls the gate at `Market.enterGate`. That gate can call a subgate to check permissions.

### `VaultV2CompatibleEnterGate`

Despite its name, this is a Midnight enter gate, not a Vault V2 gate.
Midnight calls its `canIncreaseCredit(account)` and `canIncreaseDebt(account)` functions.
One gate can be the enterGate of any number of markets.
For ordinary permission checks, the gate calls its `subGate` with the account.
During `forceDeallocate`, a Midnight adapter from a registered factory can temporarily admit a shareholder of its parent vault to receive credit without subgate approval. The adapter sells through its own offer and is the buyer callback of that sale: it clears the admission in that callback, before Midnight transfers the loan token, so neither the buyer nor the token can reuse it.

### `VaultV2CompatibleEnterGateFactory`

Deploys `VaultV2CompatibleEnterGate` contracts using `CREATE2`.
The factory records each gate in `isCreated[gate]`.

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
