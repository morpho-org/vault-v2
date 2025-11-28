// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Morpho Association

import "../helpers/UtilityFunctionsVault.spec";

using RevertCondition as RevertCondition;

// Assumptions:
// - Accrue interest is assumed to not revert.
// - The helper contract is called first, so this specification can miss trivial revert conditions like e.msg.value != 0.

methods {
    // Assume that interest accrual does not revert.
    function accrueInterest() internal => NONDET;
    // Assumption to be able to retrieve the returned value by adapter registry before it is called.
    function _.isInRegistry(address adapter) external => ghostIsInRegistry(calledContract, adapter) expect(bool);
}

ghost ghostIsInRegistry(address, address) returns bool;

rule timelockedFunctionsRevertConditions(env e, calldataarg args, method f)
filtered { f -> f.contract == currentContract && functionIsTimelocked(f) } {
    bool revertCondition;
    if (f.selector == sig:setIsAllocator(address, bool).selector) {
        revertCondition = RevertCondition.setIsAllocator(e, args);
    } else if (f.selector == sig:setReceiveSharesGate(address).selector) {
        revertCondition = RevertCondition.setReceiveSharesGate(e, args);
    } else if (f.selector == sig:setSendSharesGate(address).selector) {
        revertCondition = RevertCondition.setSendSharesGate(e, args);
    } else if (f.selector == sig:setReceiveAssetsGate(address).selector) {
        revertCondition = RevertCondition.setReceiveAssetsGate(e, args);
    } else if (f.selector == sig:setSendAssetsGate(address).selector) {
        revertCondition = RevertCondition.setSendAssetsGate(e, args);
    } else if (f.selector == sig:setAdapterRegistry(address).selector) {
        revertCondition = RevertCondition.setAdapterRegistry(e, args);
    } else if (f.selector == sig:addAdapter(address).selector) {
        revertCondition = RevertCondition.addAdapter(e, args);
    } else if (f.selector == sig:removeAdapter(address).selector) {
        revertCondition = RevertCondition.removeAdapter(e, args);
    } else if (f.selector == sig:increaseTimelock(bytes4, uint256).selector) {
        revertCondition = RevertCondition.increaseTimelock(e, args);
    } else if (f.selector == sig:decreaseTimelock(bytes4, uint256).selector) {
        revertCondition = RevertCondition.decreaseTimelock(e, args);
    } else if (f.selector == sig:abdicate(bytes4).selector) {
        revertCondition = RevertCondition.abdicate(e, args);
    } else if (f.selector == sig:setPerformanceFee(uint256).selector) {
        revertCondition = RevertCondition.setPerformanceFee(e, args);
    } else if (f.selector == sig:setManagementFee(uint256).selector) {
        revertCondition = RevertCondition.setManagementFee(e, args);
    } else if (f.selector == sig:setPerformanceFeeRecipient(address).selector) {
        revertCondition = RevertCondition.setPerformanceFeeRecipient(e, args);
    } else if (f.selector == sig:setManagementFeeRecipient(address).selector) {
        revertCondition = RevertCondition.setManagementFeeRecipient(e, args);
    } else if (f.selector == sig:increaseAbsoluteCap(bytes, uint256).selector) {
        revertCondition = RevertCondition.increaseAbsoluteCap(e, args);
    } else if (f.selector == sig:increaseRelativeCap(bytes, uint256).selector) {
        revertCondition = RevertCondition.increaseRelativeCap(e, args);
    } else if (f.selector == sig:setForceDeallocatePenalty(address, uint256).selector) {
        revertCondition = RevertCondition.setForceDeallocatePenalty(e, args);
    } else {
        revertCondition = false; // To silence a warning.
        assert false, "Unexpected selector";
    }

    f@withrevert(e, args);
    assert lastReverted <=> revertCondition;
}

rule setOwnerRevertCondition(env e, address newOwner) {
    address oldOwner = owner();
    setOwner@withrevert(e, newOwner);
    assert lastReverted <=> e.msg.value != 0 || e.msg.sender != oldOwner || newOwner == oldOwner;
}

rule setCuratorRevertCondition(env e, address newCurator) {
    address oldCurator = curator();
    setCurator@withrevert(e, newCurator);
    assert lastReverted <=> e.msg.value != 0 || e.msg.sender != oldCurator || newCurator == oldCurator;
}

rule setIsSentinelRevertCondition(env e, address account, bool newIsSentinel) {
    bool wasSentinel = isSentinel(account);
    setIsSentinel@withrevert(e, account, newIsSentinel);
    assert lastReverted <=> e.msg.value != 0 || e.msg.sender != account || newIsSentinel == wasSentinel;
}

rule setNameRevertCondition(env e, string memory newName) {
    string memory oldName = name();
    setName@withrevert(e, newName);
    assert lastReverted <=> e.msg.value != 0 || e.msg.sender != oldName || newName == oldName;
}

rule setSymbolRevertCondition(env e, string memory newSymbol) {
    string memory oldSymbol = symbol();
    setSymbol@withrevert(e, newSymbol);
    assert lastReverted <=> e.msg.value != 0 || e.msg.sender != oldSymbol || newSymbol == oldSymbol;
}

rule submitRevertCondition(env e, bytes data) {
    uint256 executableAt = executableAt(data);
    submit@withrevert(e, data);
    assert lastReverted <=> e.msg.value != 0 || e.msg.sender != executableAt || executableAt != 0;
}

rule revokeRevertCondition(env e, bytes data) {
    uint256 executableAt = executableAt(data);
    revoke@withrevert(e, data);
    assert lastReverted <=> e.msg.value != 0 || e.msg.sender != executableAt || executableAt != 0;
}

rule decreaseAbsoluteCapRevertCondition(env e, bytes idData, uint256 newAbsoluteCap) {
    uint256 absoluteCap = absoluteCap(idData);
    decreaseAbsoluteCap@withrevert(e, idData, newAbsoluteCap);
    assert lastReverted <=> e.msg.value != 0 || e.msg.sender != absoluteCap || newAbsoluteCap == absoluteCap;
}

rule decreaseRelativeCapRevertCondition(env e, bytes idData, uint256 newRelativeCap) {
    uint256 relativeCap = relativeCap(idData);
    decreaseRelativeCap@withrevert(e, idData, newRelativeCap);
    assert lastReverted <=> e.msg.value != 0 || e.msg.sender != relativeCap || newRelativeCap == relativeCap;
}

rule allocateInputValidation(env e, address adapter, bytes data, uint256 assets) {
    bool callerIsAllocator = isAllocator(e.msg.sender);
    bool adapterIsRegistered = isAdapter(adapter);

    allocate@withrevert(e, adapter, data, assets);
    assert !callerIsAllocator || !adapterIsRegistered => lastReverted;
}

rule deallocateInputValidation(env e, address adapter, bytes data, uint256 assets) {
    bool callerIsAllocator = isAllocator(e.msg.sender);
    bool callerIsSentinel = isSentinel(e.msg.sender);
    bool adapterIsRegistered = isAdapter(adapter);

    deallocate@withrevert(e, adapter, data, assets);
    assert !callerIsAllocator || !callerIsSentinel || !adapterIsRegistered => lastReverted;
}

rule setLiquidityAdapterAndDataRevertCondition(env e, address newLiquidityAdapter, bytes newLiquidityData) {
    bool callerIsAllocator = isAllocator(e.msg.sender);
    setLiquidityAdapterAndData@withrevert(e, newLiquidityAdapter, newLiquidityData);
    assert !callerIsAllocator <=> e.msg.value != 0 || !callerIsAllocator;
}

rule setMaxRateRevertCondition(env e, uint256 newMaxRate) {
    bool callerIsAllocator = isAllocator(e.msg.sender);
    setMaxRate@withrevert(e, newMaxRate);
    assert !callerIsAllocator <=> e.msg.value != 0 || newMaxRate > MAX_MAX_RATE;
}

rule transferInputValidation(env e, address from, address to, uint256 shares) {
    bool toIsZeroAddress = to == address(0);
    bool callerCanSendShares = canSendShares(e.msg.sender);
    bool toCanReceiveShares = canReceiveShares(to);

    transfer@withrevert(e, from, to, shares);
    assert !toIsZeroAddress || !callerCanSendShares || !toCanReceiveShares => lastReverted;
}

rule transferFromInputValidation(env e, address from, address to, uint256 shares) {
    bool fromIsZeroAddress = from == address(0);
    bool toIsZeroAddress = to == address(0);
    bool fromCanSendShares = canSendShares(from);
    bool toCanReceiveShares = canReceiveShares(to);

    transferFrom@withrevert(e, from, to, shares);
    assert !fromIsZeroAddress || !toIsZeroAddress || !fromCanSendShares || !toCanReceiveShares => lastReverted;
}
