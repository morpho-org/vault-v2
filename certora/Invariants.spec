// SPDX-License-Identifier: GPL-2.0-or-later

methods {
    function multicall(bytes[]) external => NONDET DELETE;

    function performanceFee() external returns uint256 envfree;
    function performanceFeeRecipient() external returns address envfree;
    function managementFee() external returns uint256 envfree;
    function managementFeeRecipient() external returns address envfree;

    function absoluteCap(bytes32 id) external returns uint256 envfree;
    function relativeCap(bytes32 id) external returns uint256 envfree;
    function allocation(bytes32 id) external returns uint256 envfree;
    function timelock(bytes4 selector) external returns uint256 envfree;
    function liquidityAdapter() external returns address envfree;
    function liquidityData() external returns bytes memory envfree;

    function isAdapter(address adapter) external returns bool envfree;

    function totalAssets() external returns uint256 envfree;
    function balanceOf(address) external returns uint256 envfree;
}

definition TIMELOCK_CAP() returns uint256 = 14 * 24 * 60 * 60;
definition MAX_PERFOMANCE_FEE() returns uint256 = 10^18 / 2;
definition MAX_MANAGEMENT_FEE() returns uint256 = 10^18 / 20 / (365 * 24 * 60 * 60);


strong invariant performanceFeeRecipient()
    performanceFee() != 0 => performanceFeeRecipient() != 0;

strong invariant managementFeeRecipient()
    managementFee() != 0 => managementFeeRecipient() != 0;

strong invariant performanceFee()
    performanceFee() <= MAX_PERFOMANCE_FEE();

strong invariant managementFee()
    managementFee() <= MAX_MANAGEMENT_FEE();

strong invariant balanceOfZero()
    balanceOf(0) == 0;

strong invariant timelockCapExceptSetGate(bytes4 selector)
    selector != to_bytes4(0x88315a40) => timelock(selector) <= TIMELOCK_CAP();

strong invariant timelockSetGate()
    timelock(to_bytes4(0x88315a40)) <= TIMELOCK_CAP() || timelock(to_bytes4(0x88315a40)) == max_uint256;

strong invariant timelockTimelock()
    timelock(to_bytes4(0x5c1a1a4f)) == TIMELOCK_CAP();

strong invariant liquidityAdapterInvariant()
    liquidityAdapter() == 0 || isAdapter(liquidityAdapter());
