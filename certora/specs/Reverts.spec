// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Morpho Association

import "../helpers/UtilityVault.spec";

using RevertCondition as RevertCondition;
using Utils as Utils;
using VaultV2 as VaultV2;

// This specification checks either the revert condition or the input validation under which a function reverts.
// Interest accrual is assumed to not revert.

methods {
    function Utils.maxMaxRate() external returns (uint256) envfree;
    function Utils.getStringLength(string s) external returns (uint256) envfree;

    // Assume that accrueInterest does not revert.
    function accrueInterest() internal => NONDET;

    // Trick to be able to retrieve the value returned by the corresponding contract before it is called, without the value changing between the retrieval and the call.
    function _.isInRegistry(address adapter) external => ghostIsInRegistry(calledContract, adapter) expect(bool);
    function _.canSendShares(address account) external => ghostCanSendShares(calledContract, account) expect(bool);
    function _.canReceiveShares(address account) external => ghostCanReceiveShares(calledContract, account) expect(bool);
    function _.canSendAssets(address account) external => ghostCanSendAssets(calledContract, account) expect(bool);
    function _.canReceiveAssets(address account) external => ghostCanReceiveAssets(calledContract, account) expect(bool);
    function _.deallocate(bytes data, uint256 assets, bytes4 selector, address sender) external with(env e) => summaryDeallocate(e, data, assets, selector, sender) expect(bytes32[], int256);
}

ghost ghostIsInRegistry(address, address) returns bool;

ghost ghostCanSendShares(address, address) returns bool;

ghost ghostCanReceiveShares(address, address) returns bool;

ghost ghostCanSendAssets(address, address) returns bool;

ghost ghostCanReceiveAssets(address, address) returns bool;

function summaryDeallocate(env e, bytes data, uint256 assets, bytes4 selector, address sender) returns (bytes32[], int256) {
    bytes32[] ids;
    int256 change;
    require ids.length == 3, "see IdsMorphoMarketV1Adapter";

    //require ids[0] != ids[1], "ack";
    //require ids[0] != ids[2], "ack";
    //require ids[1] != ids[2], "ack";
    //require forall uint256 i. i < ids.length => currentContract.caps[ids[i]].allocation > 0, "assume that the allocation is positive";
    //require forall uint256 i. i < ids.length => currentContract.caps[ids[i]].allocation < 2 ^ 20 * 2 ^ 128, "market v1 fits total supply assets on 128 bits, and assume at most 2^20 markets";
    //require change < 2 ^ 128, "market v1 fits total supply assets on 128 bits";
    return (ids, change);
}

// The helper contract is called first, so this specification can miss trivial revert conditions like e.msg.value != 0.
rule timelockedFunctionsRevertConditions(env e, calldataarg args, method f) filtered { f -> f.contract == currentContract && functionIsTimelocked(f) } {
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
    address owner = owner();
    setOwner@withrevert(e, newOwner);
    assert lastReverted <=> e.msg.value != 0 || e.msg.sender != owner;
}

rule setCuratorRevertCondition(env e, address newCurator) {
    address owner = owner();
    setCurator@withrevert(e, newCurator);
    assert lastReverted <=> e.msg.value != 0 || e.msg.sender != owner;
}

rule setIsSentinelRevertCondition(env e, address account, bool newIsSentinel) {
    address owner = owner();
    setIsSentinel@withrevert(e, account, newIsSentinel);
    assert lastReverted <=> e.msg.value != 0 || e.msg.sender != owner;
}

rule setNameRevertCondition(env e, string newName) {
    address owner = owner();
    Utils.getStringLength@withrevert(name());
    assert !lastReverted;

    setName@withrevert(e, newName);

    assert (e.msg.value != 0 || e.msg.sender != owner) <=> lastReverted;
}

rule setSymbolRevertCondition(env e, string newSymbol) {
    address owner = owner();
    Utils.getStringLength@withrevert(symbol());
    assert !lastReverted;

    setSymbol@withrevert(e, newSymbol);

    assert (e.msg.value != 0 || e.msg.sender != owner) <=> lastReverted;
}

rule submitInputValidation(env e, bytes data) {
    address curator = curator();
    uint256 executableAtData = executableAt(data);
    submit@withrevert(e, data);
    assert e.msg.value != 0 || e.msg.sender != curator || executableAtData != 0 => lastReverted;
}

rule revokeRevertCondition(env e, bytes data) {
    address curator = curator();
    bool isSentinel = isSentinel(e.msg.sender);
    uint256 executableAtData = executableAt(data);
    revoke@withrevert(e, data);
    assert lastReverted <=> e.msg.value != 0 || (e.msg.sender != curator && !isSentinel) || executableAtData == 0;
}

rule decreaseAbsoluteCapRevertCondition(env e, bytes idData, uint256 newAbsoluteCap) {
    address curator = curator();
    bool isSentinel = isSentinel(e.msg.sender);
    uint256 absoluteCap = absoluteCap(keccak256(idData));
    decreaseAbsoluteCap@withrevert(e, idData, newAbsoluteCap);
    assert lastReverted <=> e.msg.value != 0 || (e.msg.sender != curator && !isSentinel) || newAbsoluteCap > absoluteCap;
}

rule decreaseRelativeCapRevertCondition(env e, bytes idData, uint256 newRelativeCap) {
    address curator = curator();
    bool isSentinel = isSentinel(e.msg.sender);
    uint256 relativeCap = relativeCap(keccak256(idData));
    decreaseRelativeCap@withrevert(e, idData, newRelativeCap);
    assert lastReverted <=> e.msg.value != 0 || (e.msg.sender != curator && !isSentinel) || newRelativeCap > relativeCap;
}

rule allocateInputValidation(env e, address adapter, bytes data, uint256 assets) {
    bool callerIsAllocator = isAllocator(e.msg.sender);
    bool adapterIsRegistered = isAdapter(adapter);

    allocate@withrevert(e, adapter, data, assets);
    assert !callerIsAllocator || !adapterIsRegistered => lastReverted;
}

rule deallocateRevertCondition(env e, address adapter, bytes data, uint256 assets) {
    bool callerIsAllocator = isAllocator(e.msg.sender);
    bool callerIsSentinel = isSentinel(e.msg.sender);
    bool adapterIsRegistered = isAdapter(adapter);

    deallocate@withrevert(e, adapter, data, assets);
    assert !(callerIsAllocator || callerIsSentinel) || !adapterIsRegistered || e.msg.value != 0 <=> lastReverted;
}

rule forceDeallocateInputValidation(env e, address adapter, bytes data, uint256 assets, address onBehalf) {
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
