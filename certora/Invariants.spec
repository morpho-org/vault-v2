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
}

/// INVARIANTS ///

strong invariant performanceFeeRecipient()
    performanceFee() != 0 => performanceFeeRecipient() != 0;

strong invariant managementFeeRecipient()
    managementFee() != 0 => managementFeeRecipient() != 0;

strong invariant relativeCaps(bytes32 id)
    allocation(id) <= totalAssets() * relativeCap(id) / 1000000000000000000;

strong invariant relativeCapsList(bytes32 id)
    relativeCap(id) != 0 => idsWithRelativeCap.contains(id);

strong invariant absoluteCaps(bytes32 id)
    allocation(id) <= absoluteCap(id)
{
    preserved decreaseAbsoluteCap(bytes32 _id, uint256 _absoluteCap) with (env e) {
        require allocation(_id) <= _absoluteCap;
    }
}
