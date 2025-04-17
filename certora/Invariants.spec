// SPDX-License-Identifier: GPL-2.0-or-later

methods {
    function performanceFee() external returns uint256 envfree;
    function performanceFeeRecipient() external returns address envfree;
    function managementFee() external returns uint256 envfree;
    function managementFeeRecipient() external returns address envfree;

    function absoluteCap(bytes32 id) external returns uint256 envfree;
    function relativeCap(bytes32 id) external returns uint256 envfree;
    function allocation(bytes32 id) external returns uint256 envfree;

    function totalAssets() external returns uint256 envfree;
    function totalSupply() external returns uint256 envfree;
    function withdrawableShares() external returns uint256 envfree;
}

/// INVARIANTS ///

strong invariant performanceFeeRecipient()
    performanceFee() != 0 => performanceFeeRecipient() != 0;

strong invariant managementFeeRecipient()
    managementFee() != 0 => managementFeeRecipient() != 0;

strong invariant withdrawableShares()
    withdrawableShares() <= totalSupply() / 10;

// you can never withdraw more than 10% atomically
rule withrawableShares(method f, env e, calldataarg args) {
    uint256 totalSupplyBefore = totalSupply();

    f(e, args);

    assert(totalSupply() >= totalSupplyBefore * 9 / 10);
}
