// SPDX-License-Identifier: GPL-2.0-or-later

methods {
    function performanceFee() external returns uint256 envfree;
    function performanceFeeRecipient() external returns address envfree;
    function managementFee() external returns uint256 envfree;
    function managementFeeRecipient() external returns address envfree;

    function _.protocolFee() external returns uint256 envfree;
    function _.protocolFeeRecipient() external returns address envfree;
}

/// INVARIANTS ///

strong invariant performanceFeeRecipient(bytes32 id)
    performanceFee() != 0 => performanceFeeRecipient() != 0;

strong invariant managementFeeRecipient(bytes32 id)
    managementFee() != 0 => managementFeeRecipient() != 0;

