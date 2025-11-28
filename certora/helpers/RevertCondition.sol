// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Morpho Association
pragma solidity 0.8.28;

import "../../src/VaultV2.sol";
import "../../src/interfaces/IVaultV2.sol";
import "../../src/interfaces/IAdapterRegistry.sol";
import {
    WAD,
    MAX_PERFORMANCE_FEE,
    MAX_MANAGEMENT_FEE,
    MAX_FORCE_DEALLOCATE_PENALTY
} from "../../src/libraries/ConstantsLib.sol";

/// Helper in getting revert conditions for timelocked functions.
contract RevertCondition {
    VaultV2 public vault;

    function timelockFails() internal view returns (bool) {
        uint256 executableAtData = vault.executableAt(msg.data);
        bool dataNotSubmitted = executableAtData == 0;
        bool timelockNotExpired = block.timestamp < executableAtData;
        bool functionAbdicated = vault.abdicated(bytes4(msg.data));
        return dataNotSubmitted || timelockNotExpired || functionAbdicated;
    }

    function setIsAllocator(address, bool) external view returns (bool) {
        return timelockFails();
    }

    function setReceiveSharesGate(address) external view returns (bool) {
        return timelockFails();
    }

    function setSendSharesGate(address) external view returns (bool) {
        return timelockFails();
    }

    function setReceiveAssetsGate(address) external view returns (bool) {
        return timelockFails();
    }

    function setSendAssetsGate(address) external view returns (bool) {
        return timelockFails();
    }

    function setAdapterRegistry(address newAdapterRegistry) external view returns (bool revertCondition) {
        revertCondition = timelockFails();

        if (newAdapterRegistry != address(0)) {
            uint256 adaptersLength = vault.adaptersLength();
            for (uint256 i = 0; i < adaptersLength; i++) {
                address adapter = vault.adapters(i);
                revertCondition = revertCondition || !IAdapterRegistry(newAdapterRegistry).isInRegistry(adapter);
            }
        }
    }

    function addAdapter(address account) external view returns (bool revertCondition) {
        revertCondition = timelockFails();

        address registry = vault.adapterRegistry();
        revertCondition =
            revertCondition || (registry != address(0) && !IAdapterRegistry(registry).isInRegistry(account));
    }

    function removeAdapter(address) external view returns (bool) {
        return timelockFails();
    }

    function increaseTimelock(bytes4 targetSelector, uint256 newDuration) external view returns (bool revertCondition) {
        revertCondition = timelockFails();
        revertCondition = revertCondition || targetSelector == IVaultV2.decreaseTimelock.selector;
        revertCondition = revertCondition || newDuration < vault.timelock(targetSelector);
    }

    function decreaseTimelock(bytes4 targetSelector, uint256 newDuration) external view returns (bool revertCondition) {
        revertCondition = timelockFails();
        revertCondition = revertCondition || targetSelector == IVaultV2.decreaseTimelock.selector;
        revertCondition = revertCondition || newDuration > vault.timelock(targetSelector);
    }

    function abdicate(bytes4) external view returns (bool) {
        return timelockFails();
    }

    function setPerformanceFee(uint256 newPerformanceFee) external view returns (bool revertCondition) {
        revertCondition = timelockFails();
        revertCondition = revertCondition || newPerformanceFee > MAX_PERFORMANCE_FEE;
        revertCondition = revertCondition || (vault.performanceFeeRecipient() == address(0) && newPerformanceFee > 0);
    }

    function setManagementFee(uint256 newManagementFee) external view returns (bool revertCondition) {
        revertCondition = timelockFails();
        revertCondition = revertCondition || newManagementFee > MAX_MANAGEMENT_FEE;
        revertCondition = revertCondition || (vault.managementFeeRecipient() == address(0) && newManagementFee > 0);
    }

    function setPerformanceFeeRecipient(address newPerformanceFeeRecipient)
        external
        view
        returns (bool revertCondition)
    {
        revertCondition = timelockFails();
        revertCondition = revertCondition || newPerformanceFeeRecipient == address(0) && vault.performanceFee() > 0;
    }

    function setManagementFeeRecipient(address newManagementFeeRecipient) external view returns (bool revertCondition) {
        revertCondition = timelockFails();
        revertCondition = revertCondition || newManagementFeeRecipient == address(0) && vault.managementFee() > 0;
    }

    function increaseAbsoluteCap(bytes memory idData, uint256 newAbsoluteCap)
        external
        view
        returns (bool revertCondition)
    {
        revertCondition = timelockFails();

        bytes32 id = keccak256(idData);
        uint256 currentAbsoluteCap = vault.absoluteCap(id);
        revertCondition = revertCondition || newAbsoluteCap < currentAbsoluteCap;
        revertCondition = revertCondition || newAbsoluteCap > type(uint128).max;
    }

    function increaseRelativeCap(bytes memory idData, uint256 newRelativeCap)
        external
        view
        returns (bool revertCondition)
    {
        revertCondition = timelockFails();
        revertCondition = revertCondition || newRelativeCap > WAD;

        bytes32 id = keccak256(idData);
        uint256 currentRelativeCap = vault.relativeCap(id);
        revertCondition = revertCondition || newRelativeCap < currentRelativeCap;
    }

    function setForceDeallocatePenalty(address, uint256 newForceDeallocatePenalty)
        external
        view
        returns (bool revertCondition)
    {
        revertCondition = timelockFails();
        revertCondition = revertCondition || newForceDeallocatePenalty > MAX_FORCE_DEALLOCATE_PENALTY;
    }
}
