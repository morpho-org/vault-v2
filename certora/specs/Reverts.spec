// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Morpho Association

import "../helpers/UtilityVault.spec";

using RevertCondition as RevertCondition;
using Utils as Utils;

// Assumptions:
// - Accrue interest is assumed to not revert.
// - The helper contract is called first, so this specification can miss trivial revert conditions like e.msg.value != 0.

methods {
    function Utils.maxMaxRate() external returns (uint256) envfree;

    // Assume that interest accrual does not revert.
    function accrueInterest() internal => NONDET;
    // Assumption to be able to retrieve the returned value by the corresponding contract before it is called.
    function _.isInRegistry(address adapter) external => ghostIsInRegistry(calledContract, adapter) expect(bool);
    function _.canSendShares(address account) external => ghostCanSendShares(calledContract, account) expect(bool);
    function _.canReceiveShares(address account) external => ghostCanReceiveShares(calledContract, account) expect(bool);
    function _.canSendAssets(address account) external => ghostCanSendAssets(calledContract, account) expect(bool);
    function _.canReceiveAssets(address account) external => ghostCanReceiveAssets(calledContract, account) expect(bool);
}

ghost ghostIsInRegistry(address, address) returns bool;
ghost ghostCanSendShares(address, address) returns bool;
ghost ghostCanReceiveShares(address, address) returns bool;
ghost ghostCanSendAssets(address, address) returns bool;
ghost ghostCanReceiveAssets(address, address) returns bool;

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
    assert lastReverted <=> e.msg.value != 0 || e.msg.sender != oldOwner;
}

rule setCuratorRevertCondition(env e, address newCurator) {
    address oldOwner = owner();
    setCurator@withrevert(e, newCurator);
    assert lastReverted <=> e.msg.value != 0 || e.msg.sender != oldOwner;
}

rule setIsSentinelRevertCondition(env e, address account, bool newIsSentinel) {
    address oldOwner = owner();
    setIsSentinel@withrevert(e, account, newIsSentinel);
    assert lastReverted <=> e.msg.value != 0 || e.msg.sender != oldOwner;
}

rule setNameInputValidation(env e, string newName) {
    address oldOwner = owner();
    setName@withrevert(e, newName);
    assert e.msg.value != 0 || e.msg.sender != oldOwner => lastReverted;
}

rule setSymbolInputValidation(env e, string newSymbol) {
    address oldOwner = owner();
    setSymbol@withrevert(e, newSymbol);
    assert e.msg.value != 0 || e.msg.sender != oldOwner => lastReverted;
}

rule submitInputValidation(env e, bytes data) {
    address oldCurator = curator();
    uint256 executableAtData = executableAt(data);
    submit@withrevert(e, data);
    assert e.msg.value != 0 || e.msg.sender != oldCurator || executableAtData != 0 => lastReverted;
}

rule revokeRevertCondition(env e, bytes data) {
    address oldCurator = curator();
    bool isSentinel = isSentinel(e.msg.sender);
    uint256 executableAtData = executableAt(data);
    revoke@withrevert(e, data);
    assert lastReverted <=> e.msg.value != 0 || (e.msg.sender != oldCurator && !isSentinel) || executableAtData == 0;
}

rule decreaseAbsoluteCapRevertCondition(env e, bytes idData, uint256 newAbsoluteCap) {
    address oldCurator = curator();
    bool isSentinel = isSentinel(e.msg.sender);
    uint256 oldAbsoluteCap = absoluteCap(keccak256(idData));
    decreaseAbsoluteCap@withrevert(e, idData, newAbsoluteCap);
    assert lastReverted <=> e.msg.value != 0 || (e.msg.sender != oldCurator && !isSentinel) || newAbsoluteCap > oldAbsoluteCap;
}

rule decreaseRelativeCapRevertCondition(env e, bytes idData, uint256 newRelativeCap) {
    address oldCurator = curator();
    bool isSentinel = isSentinel(e.msg.sender);
    uint256 oldRelativeCap = relativeCap(keccak256(idData));
    decreaseRelativeCap@withrevert(e, idData, newRelativeCap);
    assert lastReverted <=> e.msg.value != 0 || (e.msg.sender != oldCurator && !isSentinel) || newRelativeCap > oldRelativeCap;
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
    assert !(callerIsAllocator || callerIsSentinel) || !adapterIsRegistered => lastReverted;
}

function forceDeallocateInputValidation(env e, address adapter, bytes data, uint256 assets, address onBehalf) {
    bool adapterIsRegistered = isAdapter(adapter);

    forceDeallocate@withrevert(e, adapter, data, assets, onBehalf);
    assert !adapterIsRegistered => lastReverted;
}

rule setLiquidityAdapterAndDataInputValidation(env e, address newLiquidityAdapter, bytes newLiquidityData) {
    bool callerIsAllocator = isAllocator(e.msg.sender);
    setLiquidityAdapterAndData@withrevert(e, newLiquidityAdapter, newLiquidityData);
    assert e.msg.value != 0 || !callerIsAllocator => lastReverted;
}

rule setMaxRateRevertCondition(env e, uint256 newMaxRate) {
    bool callerIsAllocator = isAllocator(e.msg.sender);
    uint256 maxMaxRate = Utils.maxMaxRate();
    setMaxRate@withrevert(e, newMaxRate);
    assert lastReverted <=> e.msg.value != 0 || !callerIsAllocator || newMaxRate > maxMaxRate;
}

rule transferInputValidation(env e, address to, uint256 shares) {
    bool toIsZeroAddress = to == 0;
    bool callerCanSendShares = canSendShares(e.msg.sender);
    bool toCanReceiveShares = canReceiveShares(to);

    transfer@withrevert(e, to, shares);
    assert toIsZeroAddress || !callerCanSendShares || !toCanReceiveShares => lastReverted;
}

rule transferFromInputValidation(env e, address from, address to, uint256 shares) {
    bool fromIsZeroAddress = from == 0;
    bool toIsZeroAddress = to == 0;
    bool fromCanSendShares = canSendShares(from);
    bool toCanReceiveShares = canReceiveShares(to);

    transferFrom@withrevert(e, from, to, shares);
    assert fromIsZeroAddress || toIsZeroAddress || !fromCanSendShares || !toCanReceiveShares => lastReverted;
}
