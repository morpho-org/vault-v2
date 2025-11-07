// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Morpho Association
pragma solidity 0.8.28;

import "../../src/VaultV2.sol";
import "../../src/interfaces/IVaultV2.sol";
import "../../src/interfaces/IAdapterRegistry.sol";
import {WAD, MAX_PERFORMANCE_FEE, MAX_MANAGEMENT_FEE, MAX_FORCE_DEALLOCATE_PENALTY} from "../../src/libraries/ConstantsLib.sol";

/// Helper verifying timelocked functions can execute when conditions are met
contract ExecutableAtHelpers {
    VaultV2 public vault;
    
    function checkTimelockConditions() internal view {
        uint256 executableAtData = vault.executableAt(msg.data);
        require(executableAtData != 0, "Data not submitted");
        require(block.timestamp >= executableAtData, "Timelock not expired");
        bytes4 selector = bytes4(msg.data);
        require(!vault.abdicated(selector), "Function is abdicated");
    }
    
    // ============================================================================
    // TIMELOCKED FUNCTIONS - Match VaultV2 signatures
    // ============================================================================
    
    function setIsAllocator(address account, bool newIsAllocator) external {
        checkTimelockConditions();
    }
    
    function setReceiveSharesGate(address newReceiveSharesGate) external {
        checkTimelockConditions();
    }
    
    function setSendSharesGate(address newSendSharesGate) external {
        checkTimelockConditions();
    }
    
    function setReceiveAssetsGate(address newReceiveAssetsGate) external {
        checkTimelockConditions();
    }
    
    function setSendAssetsGate(address newSendAssetsGate) external {
        checkTimelockConditions();
    }
    
    function setAdapterRegistry(address newAdapterRegistry) external {
        checkTimelockConditions();
        
        // If setting a non-zero registry, it must include all existing adapters
        if (newAdapterRegistry != address(0)) {
            uint256 adaptersLength = vault.adaptersLength();
            for (uint256 i = 0; i < adaptersLength; i++) {
                address adapter = vault.adapters(i);
                require(
                    IAdapterRegistry(newAdapterRegistry).isInRegistry(adapter),
                    "Adapter not in new registry"
                );
            }
        }
    }
    
    function addAdapter(address account) external {
        checkTimelockConditions();
        
        // If adapter registry is set, adapter must be in registry
        address registry = vault.adapterRegistry();
        require(
            registry == address(0) || IAdapterRegistry(registry).isInRegistry(account),
            "Adapter not in registry"
        );
    }
    
    function removeAdapter(address account) external {
        checkTimelockConditions();
    }
    
    function increaseTimelock(bytes4 targetSelector, uint256 newDuration) external {
        checkTimelockConditions();
        require(targetSelector != IVaultV2.decreaseTimelock.selector, "Cannot timelock decreaseTimelock");
        require(newDuration >= vault.timelock(targetSelector), "Timelock not increasing");
    }
    
    function decreaseTimelock(bytes4 targetSelector, uint256 newDuration) external {
        checkTimelockConditions();
        require(targetSelector != IVaultV2.decreaseTimelock.selector, "Cannot timelock decreaseTimelock");
        require(newDuration <= vault.timelock(targetSelector), "Timelock not decreasing");
    }
    
    function abdicate(bytes4 targetSelector) external {
        checkTimelockConditions();
    }
    
    function setPerformanceFee(uint256 newPerformanceFee) external {
        checkTimelockConditions();
        require(block.timestamp >= vault.lastUpdate(), "Last update not set");
        require(block.timestamp <= vault.lastUpdate() + 315360000, "Time too far in future");
        require(newPerformanceFee <= MAX_PERFORMANCE_FEE, "Fee exceeds MAX_PERFORMANCE_FEE");
        require(
            vault.performanceFeeRecipient() != address(0) || newPerformanceFee == 0,
            "Fee invariant broken: recipient must be set if fee > 0"
        );
    }
    
    function setManagementFee(uint256 newManagementFee) external {
        checkTimelockConditions();
        require(block.timestamp >= vault.lastUpdate(), "Last update not set");
        require(block.timestamp <= vault.lastUpdate() + 315360000, "Time too far in future");
        require(newManagementFee <= MAX_MANAGEMENT_FEE, "Fee exceeds MAX_MANAGEMENT_FEE");
        require(
            vault.managementFeeRecipient() != address(0) || newManagementFee == 0,
            "Fee invariant broken: recipient must be set if fee > 0"
        );
    }
    
    function setPerformanceFeeRecipient(address newPerformanceFeeRecipient) external {
        checkTimelockConditions();
        require(block.timestamp >= vault.lastUpdate(), "Last update not set");
        require(block.timestamp <= vault.lastUpdate() + 315360000, "Time too far in future");
        require(
            newPerformanceFeeRecipient != address(0) || vault.performanceFee() == 0,
            "Fee invariant broken: recipient cannot be zero if fee > 0"
        );
    }
    
    function setManagementFeeRecipient(address newManagementFeeRecipient) external {
        checkTimelockConditions();
        require(block.timestamp >= vault.lastUpdate(), "Last update not set");
        require(block.timestamp <= vault.lastUpdate() + 315360000, "Time too far in future");
        require(uint160(newManagementFeeRecipient) == uint160(newManagementFeeRecipient), "Valid address");
        require(
            newManagementFeeRecipient != address(0) || vault.managementFee() == 0,
            "Fee invariant broken: recipient cannot be zero if fee > 0"
        );
    }
    
    function increaseAbsoluteCap(bytes memory idData, uint256 newAbsoluteCap) external {
        checkTimelockConditions();
        
        // Check that new cap is actually increasing and fits in uint128
        bytes32 id = keccak256(idData);
        uint256 currentAbsoluteCap = vault.absoluteCap(id);
        require(newAbsoluteCap >= currentAbsoluteCap, "Absolute cap not increasing");
        require(newAbsoluteCap <= type(uint128).max, "Cap exceeds uint128 max");
    }
    
    function increaseRelativeCap(bytes memory idData, uint256 newRelativeCap) external {
        checkTimelockConditions();
        require(newRelativeCap <= WAD, "Relative cap exceeds WAD (100%)");
        
        // Check that new cap is actually increasing
        bytes32 id = keccak256(idData);
        uint256 currentRelativeCap = vault.relativeCap(id);
        require(newRelativeCap >= currentRelativeCap, "Relative cap not increasing");
    }
    
    function setForceDeallocatePenalty(address adapter, uint256 newForceDeallocatePenalty) external {
        checkTimelockConditions();
        require(newForceDeallocatePenalty <= MAX_FORCE_DEALLOCATE_PENALTY, "Penalty exceeds MAX");
    }
}
