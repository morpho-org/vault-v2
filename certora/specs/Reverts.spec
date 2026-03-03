// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Morpho Association

import "../helpers/UtilityVault.spec";

using RevertCondition as RevertCondition;
using Utils as Utils;

// This specification checks either the revert condition or the input validation under which a function reverts.
// Interest accrual is assumed to not revert.

methods {
    function Utils.maxMaxRate() external returns (uint256) envfree;
    function Utils.maxPerformanceFee() external returns (uint256) envfree;
    function Utils.maxManagementFee() external returns (uint256) envfree;
    function liquidityData() external returns (bytes) envfree;
    function lastUpdate() external returns (uint64) envfree;
    function totalSupply() external returns (uint256) envfree;
    function virtualShares() external returns (uint256) envfree;
    function managementFee() external returns (uint96) envfree;

    // Assume that accrueInterest does not revert.
    function accrueInterest() internal => NONDET;

    // `balanceOf` is summarized to a bounded value.
    function _.balanceOf(address account) external => summaryBalanceOf() expect(uint256);

    function _.realAssets() external => summaryRealAssets() expect(uint256);

    // Trick to be able to retrieve the value returned by the corresponding contract before it is called, without the value changing between the retrieval and the call.
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

function summaryBalanceOf() returns uint256 {
    uint256 balance;
    require balance < 2 ^ 128, "totalAssets is bounded by 2 ^ 128; vault balance is less than totalAssets";
    return balance;
}

// Returns a value bounded by 2^126.
// sum of realAssets of each adapter should be bounded by 2 ^ 128; Since loop_iter is 3, we bound each real assets by 2 ^ 126 to avoid overflow when summing them.
function summaryRealAssets() returns uint256 {
    uint256 realAssets;
    require realAssets < 2 ^ 126;
    return realAssets;
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

    // String stored in name can be malformed, so we just call the getter to ensure that the encoding is correct.
    name();

    setName@withrevert(e, newName);

    assert (e.msg.value != 0 || e.msg.sender != owner) <=> lastReverted;
}

rule setSymbolRevertCondition(env e, string newSymbol) {
    address owner = owner();

    // String stored in symbol can be malformed, so we just call the getter to ensure that the encoding is correct.
    symbol();

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

rule forceDeallocateInputValidation(env e, address adapter, bytes data, uint256 assets, address onBehalf) {
    bool adapterIsRegistered = isAdapter(adapter);

    forceDeallocate@withrevert(e, adapter, data, assets, onBehalf);
    assert !adapterIsRegistered => lastReverted;
}

rule setLiquidityAdapterAndDataRevertCondition(env e, address newLiquidityAdapter, bytes newLiquidityData) {
    // Bytes stored in liquidityData can be malformed, so we just call the getter to ensure that the encoding is correct.
    liquidityData();
    bool callerIsAllocator = isAllocator(e.msg.sender);
    setLiquidityAdapterAndData@withrevert(e, newLiquidityAdapter, newLiquidityData);
    assert e.msg.value != 0 || !callerIsAllocator <=> lastReverted;
}

rule setMaxRateRevertCondition(env e, uint256 newMaxRate) {
    bool callerIsAllocator = isAllocator(e.msg.sender);
    uint256 maxMaxRate = Utils.maxMaxRate();
    setMaxRate@withrevert(e, newMaxRate);
    assert lastReverted <=> e.msg.value != 0 || !callerIsAllocator || newMaxRate > maxMaxRate;
}

rule transferRevertCondition(env e, address to, uint256 shares) {
    bool toIsZeroAddress = to == 0;
    bool callerCanSendShares = canSendShares(e.msg.sender);
    bool toCanReceiveShares = canReceiveShares(to);
    bool boundedBalance = to != e.msg.sender => shares + balanceOf(to) <= max_uint256;
    bool sufficientBalance = shares <= balanceOf(e.msg.sender);

    transfer@withrevert(e, to, shares);
    assert toIsZeroAddress || !callerCanSendShares || !toCanReceiveShares || e.msg.value != 0 || !boundedBalance || !sufficientBalance <=> lastReverted;
}

rule transferFromRevertCondition(env e, address from, address to, uint256 shares) {
    bool fromIsZeroAddress = from == 0;
    bool toIsZeroAddress = to == 0;
    bool fromCanSendShares = canSendShares(from);
    bool toCanReceiveShares = canReceiveShares(to);
    bool sufficientAllowance = e.msg.sender != from => (shares <= allowance(from, e.msg.sender));
    bool boundedBalance = to != from => shares + balanceOf(to) <= max_uint256;
    bool sufficientBalance = shares <= balanceOf(from);

    transferFrom@withrevert(e, from, to, shares);
    assert fromIsZeroAddress || toIsZeroAddress || !fromCanSendShares || !toCanReceiveShares || !sufficientAllowance || !boundedBalance || !sufficientBalance || e.msg.value != 0 <=> lastReverted;
}

rule accrueInterestViewRevertCondition(env e) {
    require(e.msg.value == 0, "setup the call");
    require(e.block.timestamp >= currentContract.lastUpdate(), "current block timestamp should be greater than or equal to lastUpdate");
    require(totalSupply() < 2 ^ 128, "totalSupply is bounded by 2 ^ 128");
    require(virtualShares() < 10 ^ 18, "virtualShares is bounded by 10 ^ 18");
    require(performanceFee() < Utils.maxPerformanceFee(), "see PerformanceFeeBound invariant in Invariants.spec; bounded by 0.5 * 10 ^ 18");
    require(managementFee() < Utils.maxManagementFee(), "see ManagementFeeBound invariant in Invariants.spec;  bounded by 0.05 * 10 ^ 18 / 365 days");
    require(e.block.timestamp - currentContract.lastUpdate() < 10 * 365 * 24 * 60 * 60, "current block timestamp should be < 10 years from lastUpdate");
    require(currentContract._totalAssets < 2 ^ 116, "totalAssets is bounded by 10 ^ 35");
    require(maxRate() < Utils.maxMaxRate(), "see maxRateBound invariant in Invariants.spec; maxRate is bounded by 2 * 10 ^ 18 / 365 days");

    uint256 newTotalAssets;
    uint256 performanceFeeShares;
    uint256 managementFeeShares;
    (newTotalAssets, performanceFeeShares, managementFeeShares) = accrueInterestView@withrevert(e);

    assert !lastReverted;
    assert newTotalAssets < 2 ^ 128;
    assert performanceFeeShares < 2 ^ 245;
    assert managementFeeShares < 2 ^ 245;
}
