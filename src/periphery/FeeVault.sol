// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {IVaultV2Factory} from "../interfaces/IVaultV2Factory.sol";
import {IVaultV2} from "../interfaces/IVaultV2.sol";
import {IMorphoVaultV1AdapterFactory} from "../adapters/interfaces/IMorphoVaultV1AdapterFactory.sol";

contract FeeVaultFactory {

    /// @dev Creates a VaultV2 with abdicated curator functions and MorphoVaultV1Adapter as liquidity adapter.
    /// @dev The caller must be the owner. The function sets the curator to the owner and prepares all configuration.
    /// @param owner The owner of the vault.
    /// @param asset The asset token address.
    /// @param salt The salt for deterministic deployment.
    /// @param morphoVaultV1AdapterFactory The factory for creating MorphoVaultV1Adapter.
    /// @param morphoVaultV2 The Morpho Vault V2 address to use with the adapter.
    /// @return vault The address of the created VaultV2.
    function createFeeVault(
        address owner,
        address asset,
        bytes32 salt,
        address morphoVaultV1AdapterFactory,
        address morphoVaultV2Factory,
        address morphoVaultV2
    ) external returns (address vault) {
        // Create the vault
        address newVaultV2 = IVaultV2Factory(morphoVaultV2Factory).createVaultV2(owner, asset, salt);
        IVaultV2 vaultInstance = IVaultV2(newVaultV2);

        // Set curator to owner
        vaultInstance.setCurator(owner);

        // Create the MorphoVaultV1Adapter
        address morphoVaultV1Adapter = IMorphoVaultV1AdapterFactory(morphoVaultV1AdapterFactory).createMorphoVaultV1Adapter(newVaultV2, morphoVaultV2);

        // Submit: Add adapter
        bytes memory addAdapterData = abi.encodeCall(IVaultV2.addAdapter, (morphoVaultV1Adapter));
        vaultInstance.submit(addAdapterData);
        vaultInstance.addAdapter(morphoVaultV1Adapter);

        // Submit: Set owner as allocator
        bytes memory setIsAllocatorData = abi.encodeCall(IVaultV2.setIsAllocator, (owner, true));
        vaultInstance.submit(setIsAllocatorData);
        vaultInstance.setIsAllocator(owner, true);

        // Set liquidity data
        bytes memory setLiquidityAdapterAndDataData = abi.encodeCall(IVaultV2.setLiquidityAdapterAndData, (morphoVaultV1Adapter, hex""));
        vaultInstance.submit(setLiquidityAdapterAndDataData);
        vaultInstance.setLiquidityAdapterAndData(morphoVaultV1Adapter, hex"");

        // Submit: Remove allocator
        bytes memory removeAllocatorData = abi.encodeCall(IVaultV2.setIsAllocator, (owner, false));
        vaultInstance.submit(removeAllocatorData);
        vaultInstance.setIsAllocator(owner, false);

        // Submit: Abdicate setIsAllocator
        bytes memory abdicateSetIsAllocatorData = abi.encodeCall(IVaultV2.abdicate, (IVaultV2.setIsAllocator.selector));
        vaultInstance.submit(abdicateSetIsAllocatorData);
        vaultInstance.abdicate(IVaultV2.setIsAllocator.selector);

        // Submit: Abdicate setAdapterRegistry
        bytes memory abdicateSetAdapterRegistryData =
            abi.encodeCall(IVaultV2.abdicate, (IVaultV2.setAdapterRegistry.selector));
        vaultInstance.submit(abdicateSetAdapterRegistryData);
        vaultInstance.abdicate(IVaultV2.setAdapterRegistry.selector);

        // Submit: Abdicate addAdapter
        bytes memory abdicateAddAdapterData = abi.encodeCall(IVaultV2.abdicate, (IVaultV2.addAdapter.selector));
        vaultInstance.submit(abdicateAddAdapterData);
        vaultInstance.abdicate(IVaultV2.addAdapter.selector);

        // Submit: Abdicate removeAdapter
        bytes memory abdicateRemoveAdapterData = abi.encodeCall(IVaultV2.abdicate, (IVaultV2.removeAdapter.selector));
        vaultInstance.submit(abdicateRemoveAdapterData);
        vaultInstance.abdicate(IVaultV2.removeAdapter.selector);

        return newVaultV2;
    }
}
