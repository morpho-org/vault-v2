// SPDX-License-Identifier: GPL-2.0-or-later

methods {
    function multicall(bytes[]) external => NONDET DELETE;

    function performanceFee() external returns uint96 envfree;
    function performanceFeeRecipient() external returns address envfree;
    function managementFee() external returns uint96 envfree;
    function managementFeeRecipient() external returns address envfree;

    function forceDeallocatePenalty(address) external returns uint256 envfree;

    function absoluteCap(bytes32 id) external returns uint256 envfree;
    function relativeCap(bytes32 id) external returns uint256 envfree;
    function allocation(bytes32 id) external returns uint256 envfree;
    function timelock(bytes4 selector) external returns uint256 envfree;
    function liquidityAdapter() external returns address envfree;
    function liquidityData() external returns bytes memory envfree;

    function isAdapter(address adapter) external returns bool envfree;

    function totalAssets() external returns uint256 envfree;
    function balanceOf(address) external returns uint256 envfree;

    function setExitGate(address) external;
    function setEnterGate(address) external;
    function decreaseTimelock(address) external;
}

definition TIMELOCK_CAP() returns uint256 = 14 * 24 * 60 * 60;
definition MAX_PERFOMANCE_FEE() returns uint256 = 10^18 / 2;
definition MAX_MANAGEMENT_FEE() returns uint256 = 10^18 / 20 / (365 * 24 * 60 * 60);
definition MAX_FORCE_DEALLOCATE_PENALTY() returns uint256 = 10^18 / 100;

definition setExitGateSelector() returns bytes4 = to_bytes4(sig:setExitGate(address).selector);
definition setEnterGateSelector() returns bytes4 = to_bytes4(sig:setEnterGate(address).selector);
definition decreaseTimelockSelector() returns bytes4 = to_bytes4(sig:decreaseTimelock(bytes4,uint256).selector);




strong invariant performanceFeeRecipient()
    performanceFee() != 0 => performanceFeeRecipient() != 0;

strong invariant managementFeeRecipient()
    managementFee() != 0 => managementFeeRecipient() != 0;

strong invariant performanceFee()
    performanceFee() <= MAX_PERFOMANCE_FEE();

strong invariant managementFee()
    managementFee() <= MAX_MANAGEMENT_FEE();

strong invariant forceDeallocatePenalty(address adapter)
    forceDeallocatePenalty(adapter) <= MAX_FORCE_DEALLOCATE_PENALTY();

strong invariant balanceOfZero()
    balanceOf(0) == 0;

strong invariant timelockBounds(bytes4 selector)
    timelock(selector) <= TIMELOCK_CAP() || timelock(selector) == max_uint256;

strong invariant timelockTimelock()
    timelock(decreaseTimelockSelector()) == TIMELOCK_CAP();

strong invariant liquidityAdapterInvariant()
    liquidityAdapter() == 0 || isAdapter(liquidityAdapter());
