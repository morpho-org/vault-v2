// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Morpho Association
pragma solidity 0.8.28;

import "../../src/VaultV2.sol";
import "../../src/interfaces/IVaultV2.sol";

// Helper verifying timelocked functions revert when one of the conditions is not met
contract RevertsTimelockedHelpers {
    VaultV2 public vault;
    
    function checkShouldRevert(bytes4 targetSelector) internal view {

        bool shouldRevert = (
            vault.abdicated(targetSelector) ||
            vault.executableAt(msg.data) == 0 ||
            vault.executableAt(msg.data) > block.timestamp
        );
        require(shouldRevert, "Expected revert conditions not met");
    }
    
    // ============================================================================
    // TIMELOCKED FUNCTIONS - Check revert conditions
    // ============================================================================
    
    function setIsAllocator(address account, bool newIsAllocator) external {
        checkShouldRevert(IVaultV2.setIsAllocator.selector);
    }
    
    function setReceiveSharesGate(address newReceiveSharesGate) external {
        checkShouldRevert(IVaultV2.setReceiveSharesGate.selector);
    }
    
    function setSendSharesGate(address newSendSharesGate) external {
        checkShouldRevert(IVaultV2.setSendSharesGate.selector);
    }
    
    function setReceiveAssetsGate(address newReceiveAssetsGate) external {
        checkShouldRevert(IVaultV2.setReceiveAssetsGate.selector);
    }
    
    function setSendAssetsGate(address newSendAssetsGate) external {
        checkShouldRevert(IVaultV2.setSendAssetsGate.selector);
    }
    
    function setAdapterRegistry(address newAdapterRegistry) external {
        checkShouldRevert(IVaultV2.setAdapterRegistry.selector);
    }
    
    function addAdapter(address account) external {
        checkShouldRevert(IVaultV2.addAdapter.selector);
    }
    
    function removeAdapter(address account) external {
        checkShouldRevert(IVaultV2.removeAdapter.selector);
    }
    
    function increaseTimelock(bytes4 targetSelector, uint256 newDuration) external {
        checkShouldRevert(IVaultV2.increaseTimelock.selector);
    }
    
    function decreaseTimelock(bytes4 targetSelector, uint256 newDuration) external {
        checkShouldRevert(IVaultV2.decreaseTimelock.selector);
    }
    
    function abdicate(bytes4 targetSelector) external {
        checkShouldRevert(IVaultV2.abdicate.selector);
    }
    
    function setPerformanceFee(uint256 newPerformanceFee) external {
        checkShouldRevert(IVaultV2.setPerformanceFee.selector);
    }
    
    function setManagementFee(uint256 newManagementFee) external {
        checkShouldRevert(IVaultV2.setManagementFee.selector);
    }
    
    function setPerformanceFeeRecipient(address newPerformanceFeeRecipient) external {
        checkShouldRevert(IVaultV2.setPerformanceFeeRecipient.selector);
    }
    
    function setManagementFeeRecipient(address newManagementFeeRecipient) external {
        checkShouldRevert(IVaultV2.setManagementFeeRecipient.selector);
    }
    
    function increaseAbsoluteCap(bytes memory idData, uint256 newAbsoluteCap) external {
        checkShouldRevert(IVaultV2.increaseAbsoluteCap.selector);
    }
    
    function increaseRelativeCap(bytes memory idData, uint256 newRelativeCap) external {
        checkShouldRevert(IVaultV2.increaseRelativeCap.selector);
    }
    
    function setForceDeallocatePenalty(address adapter, uint256 newForceDeallocatePenalty) external {
        checkShouldRevert(IVaultV2.setForceDeallocatePenalty.selector);
    }
}
