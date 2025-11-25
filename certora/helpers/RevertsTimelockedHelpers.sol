// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Morpho Association
pragma solidity 0.8.28;

import "../../src/VaultV2.sol";
import "../../src/interfaces/IVaultV2.sol";

// Helper verifying timelocked functions revert when one of the conditions is not met
contract RevertsTimelockedHelpers {
    VaultV2 public vault;

    function checkShouldRevert(bytes4 targetSelector) internal view {
        bool shouldRevert =
            (vault.abdicated(targetSelector) || vault.executableAt(msg.data) == 0
                || vault.executableAt(msg.data) > block.timestamp);
        require(shouldRevert, "Expected revert conditions not met");
    }

    // ============================================================================
    // TIMELOCKED FUNCTIONS - Check revert conditions
    // ============================================================================

    function setIsAllocator(address, bool) external view {
        checkShouldRevert(IVaultV2.setIsAllocator.selector);
    }

    function setReceiveSharesGate(address) external view {
        checkShouldRevert(IVaultV2.setReceiveSharesGate.selector);
    }

    function setSendSharesGate(address) external view {
        checkShouldRevert(IVaultV2.setSendSharesGate.selector);
    }

    function setReceiveAssetsGate(address) external view {
        checkShouldRevert(IVaultV2.setReceiveAssetsGate.selector);
    }

    function setSendAssetsGate(address) external view {
        checkShouldRevert(IVaultV2.setSendAssetsGate.selector);
    }

    function setAdapterRegistry(address) external view {
        checkShouldRevert(IVaultV2.setAdapterRegistry.selector);
    }

    function addAdapter(address) external view {
        checkShouldRevert(IVaultV2.addAdapter.selector);
    }

    function removeAdapter(address) external view {
        checkShouldRevert(IVaultV2.removeAdapter.selector);
    }

    function increaseTimelock(bytes4, uint256) external view {
        checkShouldRevert(IVaultV2.increaseTimelock.selector);
    }

    function decreaseTimelock(bytes4, uint256) external view {
        checkShouldRevert(IVaultV2.decreaseTimelock.selector);
    }

    function abdicate(bytes4) external view {
        checkShouldRevert(IVaultV2.abdicate.selector);
    }

    function setPerformanceFee(uint256) external view {
        checkShouldRevert(IVaultV2.setPerformanceFee.selector);
    }

    function setManagementFee(uint256) external view {
        checkShouldRevert(IVaultV2.setManagementFee.selector);
    }

    function setPerformanceFeeRecipient(address) external view {
        checkShouldRevert(IVaultV2.setPerformanceFeeRecipient.selector);
    }

    function setManagementFeeRecipient(address) external view {
        checkShouldRevert(IVaultV2.setManagementFeeRecipient.selector);
    }

    function increaseAbsoluteCap(bytes memory, uint256) external view {
        checkShouldRevert(IVaultV2.increaseAbsoluteCap.selector);
    }

    function increaseRelativeCap(bytes memory, uint256) external view {
        checkShouldRevert(IVaultV2.increaseRelativeCap.selector);
    }

    function setForceDeallocatePenalty(address, uint256) external view {
        checkShouldRevert(IVaultV2.setForceDeallocatePenalty.selector);
    }
}
