// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Morpho Association
pragma solidity ^0.8.0;

library ErrorsLib {
    error Abdicated();
    error AbsoluteCapExceeded();
    error AbsoluteCapNotDecreasing();
    error AbsoluteCapNotIncreasing();
    error ApproveReturnedFalse();
    error ApproveReverted();
    error AutomaticallyTimelocked();
    error CannotReceiveShares();
    error CannotReceiveAssets();
    error CannotSendShares();
    error CannotSendAssets();
    // forge-lint: disable-next-item(unused-error) part of the error catalogue, kept even though no code path uses it.
    error CapExceeded();
    error CastOverflow();
    error DataAlreadyPending();
    error DataNotTimelocked();
    error FeeInvariantBroken();
    error FeeTooHigh();
    error InvalidSigner();
    error MaxRateTooHigh();
    error NoCode();
    error NotAdapter();
    error NotInAdapterRegistry();
    error PenaltyTooHigh();
    error PermitDeadlineExpired();
    error RelativeCapAboveOne();
    error RelativeCapExceeded();
    error RelativeCapNotDecreasing();
    error RelativeCapNotIncreasing();
    error TimelockNotDecreasing();
    error TimelockNotExpired();
    error TimelockNotIncreasing();
    error TransferFromReturnedFalse();
    error TransferFromReverted();
    error TransferReturnedFalse();
    error TransferReverted();
    error Unauthorized();
    error ZeroAbsoluteCap();
    error ZeroAddress();
    error ZeroAllocation();
}
