// SPDX-License-Identifier: GPL-2.0-or-later

methods {
    function performanceFee() external returns uint256 envfree;
    function performanceFeeRecipient() external returns address envfree;
    function managementFee() external returns uint256 envfree;
    function managementFeeRecipient() external returns address envfree;

    function decreaseTimelock(bytes4 functionSelector, uint256 newDuration) external;
    
    function absoluteCap(bytes32 id) external returns uint256 envfree;
    function relativeCap(bytes32 id) external returns uint256 envfree;
    function allocation(bytes32 id) external returns uint256 envfree;
    function timelock(bytes4 selector) external returns uint256 envfree;

    function totalAssets() external returns uint256 envfree;
    function balanceOf(address) external returns uint256 envfree;
}

definition WAD() returns uint256 = 10^18;
definition TIMELOCK_CAP() returns uint256 = 14 * 24 * 60 * 60;
definition MAX_PERFOMANCE_FEE() returns uint256 = 0.5 * 10^18;
definition MAX_MANAGEMENT_FEE() returns uint256 = 0.05 * 10^18 / 365.25 * 24 * 60 * 60;

/// INVARIANTS ///

strong invariant performanceFeeRecipient()
    performanceFee() != 0 => performanceFeeRecipient() != 0;

strong invariant managementFeeRecipient()
    managementFee() != 0 => managementFeeRecipient() != 0;

strong invariant performanceFee()
    performanceFee() < MAX();

strong invariant managementFee()
    managementFee() < WAD();

strong invariant balanceOfZero() 
    balanceOf(0) == 0;

strong invariant timelockCap(bytes4 selector)
    timelock(selector) <= TIMELOCK_CAP();

strong invariant timelockTimelock()
    timelock(to_bytes4(0x5c1a1a4f)) == TIMELOCK_CAP();
