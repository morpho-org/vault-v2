// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Morpho Association
pragma solidity 0.8.28;

import {IVaultV2Factory} from "../interfaces/IVaultV2Factory.sol";
import {IVaultV2} from "../interfaces/IVaultV2.sol";
import {IMorphoVaultV1AdapterFactory} from "../adapters/interfaces/IMorphoVaultV1AdapterFactory.sol";
import {MAX_MAX_RATE, WAD} from "../libraries/ConstantsLib.sol";

/// @title FeeWrapperDeployer
/// @notice Example deployer for a VaultV2 "fee wrapper" that charges fees on top of an existing vault ("child vault").
/// This configuration creates a VaultV2 that wraps an existing vault and allows
/// the owner to charge performance and/or management fees on top of it. Users deposit into the fee
/// wrapper, which automatically routes funds to the underlying vault.
/// The underlying vault is fixed and cannot be changed after deployment.
///
/// @dev This is an example of how to configure a fee wrapper VaultV2, not the only way to configure one.
///
/// FIXED:
/// - addAdapter, removeAdapter: ABDICATED
/// - Single MorphoVaultV1Adapter pointing to the underlying vault
///
/// CONFIGURABLE:
/// - Fees (performance/management), timelocks, caps, sentinels, allocators, gates, max rate, name/symbol, liquidity
/// market, registry, owner, curator, penalties
contract FeeWrapperDeployer {
    /// @dev Creates a fee wrapper VaultV2.
    /// @dev Returns the address of the fee wrapper vault.
    function createFeeWrapper(
        address morphoVaultV2Factory,
        address morphoVaultV1AdapterFactory,
        address owner,
        bytes32 salt,
        address childVault
    ) external returns (address) {
        // Create wrapper vault with this contract as temporary owner so we can configure it.

        address vault =
            IVaultV2Factory(morphoVaultV2Factory).createVaultV2(address(this), IVaultV2(childVault).asset(), salt);

        IVaultV2(vault).setCurator(address(this));

        // Create adapter and add it to the vault.

        address morphoVaultV1Adapter =
            IMorphoVaultV1AdapterFactory(morphoVaultV1AdapterFactory).createMorphoVaultV1Adapter(vault, childVault);
        bytes memory adapterIdData = abi.encode("this", morphoVaultV1Adapter);

        IVaultV2(vault).submit(abi.encodeCall(IVaultV2.addAdapter, (morphoVaultV1Adapter)));
        IVaultV2(vault).addAdapter(morphoVaultV1Adapter);

        // Abdicate addAdapter, removeAdapter, setAdapterRegistry.

        IVaultV2(vault).submit(abi.encodeCall(IVaultV2.abdicate, (IVaultV2.addAdapter.selector)));
        IVaultV2(vault).abdicate(IVaultV2.addAdapter.selector);

        IVaultV2(vault).submit(abi.encodeCall(IVaultV2.abdicate, (IVaultV2.removeAdapter.selector)));
        IVaultV2(vault).abdicate(IVaultV2.removeAdapter.selector);

        // Optional: increase cap, set allocator, and liquidity market, max rate.

        IVaultV2(vault).submit(abi.encodeCall(IVaultV2.setIsAllocator, (address(this), true)));
        IVaultV2(vault).setIsAllocator(address(this), true);

        IVaultV2(vault).submit(abi.encodeCall(IVaultV2.setIsAllocator, (owner, true)));
        IVaultV2(vault).setIsAllocator(owner, true);

        IVaultV2(vault).submit(abi.encodeCall(IVaultV2.increaseAbsoluteCap, (adapterIdData, type(uint128).max)));
        IVaultV2(vault).increaseAbsoluteCap(adapterIdData, type(uint128).max);

        IVaultV2(vault).submit(abi.encodeCall(IVaultV2.increaseRelativeCap, (adapterIdData, WAD)));
        IVaultV2(vault).increaseRelativeCap(adapterIdData, WAD);

        IVaultV2(vault).setLiquidityAdapterAndData(morphoVaultV1Adapter, hex"");

        IVaultV2(vault).setMaxRate(MAX_MAX_RATE);

        // Transfer ownership to the actual owner.

        IVaultV2(vault).submit(abi.encodeCall(IVaultV2.setIsAllocator, (address(this), false)));
        IVaultV2(vault).setIsAllocator(address(this), false);
        IVaultV2(vault).setIsSentinel(owner, true);
        IVaultV2(vault).setCurator(owner);
        IVaultV2(vault).setOwner(owner);

        return vault;
    }
}
