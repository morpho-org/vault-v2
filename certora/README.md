This folder contains the verification of the Vault V2 using CVL, Certora's Verification Language.

The core concepts can be found in the [README](../README.md) at the root of the repository.
These properties have been verified using CVL.
We first give a [high-level description](#high-level-description) of the verification and then describe the [folder and file structure](#folder-and-file-structure) of the specification files.

# High-level description

Todo: quick summary.

## Token transfers

Todo: explain flow of tokens, from vault to adapters to protocol, and in different cases (allocation, liquidity adapter, reserve), and what is being verified.
Detail the mock ERC20 contracts.

## Timelocks

Todo:

- explain the property that adapters should have, to ensure non-custodiality.
- timelock max can't change
- timelock formula

## Id system

Todo: detail the properties.

## Shares

Todo: detail when share value changes.

- rounding on interest
- increases smoothly
- except on bad debt

## Gating

Todo: detail when gating is allowed.

## Standards

Todo:

- ERC-4626 like
- ERC-20
- ERC-2612, cannot lose shares unless authorized

## Other safety properties

### Ranges

See Invariants.conf

### Sanity checks and input validation

Todo: do a Revert.conf

## Liveness properties

Todo:

- can remove adapter
- can IKR

## Protection against common attack vectors

Other common and known attack vectors are verified to not be possible on Vault V2.

### Reentrancy

Reentrancy is a common attack vector that happens when a call to a contract allows, when in a temporary state, to call the same contract again.
The state of the contract usually refers to the storage variables, which can typically hold values that are meant to be used only after the full execution of the current function.

Todo: check this.

### Extraction of value

Todo: round trip properties.

# Folder and file structure

The [`certora/specs`](specs) folder contains the following files:

- [`Invariants.spec`](specs/Invariants.spec) checks invariants about the protocol;
- [`NotRevertingCalls.spec`](specs/NotRevertingCalls.spec) checks that some calls cannot make the contract revert, ensuring liveness.

The [`certora/confs`](confs) folder contains a configuration file for each corresponding specification file.

The [`certora/helpers`](helpers) folder contains contracts meant to ease the verification.

# Getting started

Install `certora-cli` package with `pip install certora-cli`.
To verify specification files, pass to `certoraRun` the corresponding configuration file in the [`certora/confs`](confs) folder.
It requires having set the `CERTORAKEY` environment variable to a valid Certora key.
You can also pass additional arguments, notably to verify a specific rule.

# Acknowledgments

Some rules and invariants are derived from those written by the Chainsecurity team during their audit of this repository.
