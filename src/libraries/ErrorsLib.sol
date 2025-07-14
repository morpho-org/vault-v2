// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Morpho Association
pragma solidity ^0.8.0;

library ErrorsLib {
    error AbsoluteCapExceeded();
    error AbsoluteCapNotDecreasing();
    error AbsoluteCapNotIncreasing();
    error ApproveReturnedFalse();
    error ApproveReverted();
    error CannotReceiveShares();
    error CannotReceiveAssets();
    error CannotSendShares();
    error CannotSendAssets();
    error CapExceeded();
    error CastOverflow();
    error DataAlreadyPending();
    error DataNotTimelocked();
    error EnterBlocked();
    error FeeInvariantBroken();
    error FeeTooHigh();
    error InfiniteTimelock();
    error InvalidSigner();
    error NoCode();
    error NotAdapter();
    error PenaltyTooHigh();
    error PermitDeadlineExpired();
    error RelativeCapAboveOne();
    error RelativeCapExceeded();
    error RelativeCapNotDecreasing();
    error RelativeCapNotIncreasing();
    error TimelockCapIsFixed();
    error TimelockDurationTooHigh();
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
