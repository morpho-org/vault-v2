// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

library ErrorsLib {
    error NoCode();
    error TransferReverted();
    error TransferReturnedFalse();
    error TransferFromReverted();
    error TransferFromReturnedFalse();
    error FeeTooHigh();
    error PenaltyTooHigh();
    error ZeroAddress();
    error Unauthorized();
    error TimelockNotExpired();
    error TimelockCapIsFixed();
    error TimelockDurationTooHigh();
    error CapExceeded();
    error InvalidInputLength();
    error DataNotTimelocked();
    error DataAlreadyPending();
    error TimelockNotIncreasing();
    error TimelockNotDecreasing();
    error AbsoluteCapNotIncreasing();
    error AbsoluteCapNotDecreasing();
    error RelativeCapNotIncreasing();
    error RelativeCapNotDecreasing();
    error AbsoluteCapExceeded();
    error RelativeCapExceeded();
    error RelativeCapAboveOne();
    error IdNotFound();
    error NotAllocator();
    error NotAdapter();
    error FeeInvariantBroken();
    error InvalidRate();
    error PermitDeadlineExpired();
    error InvalidSigner();
    error LiquidityAdapterInvariantBroken();
    error ApproveReverted();
    error ApproveReturnedFalse();
    error InfiniteTimelock();
    error CannotExit();
    error CannotEnter();
    error RelativeCapZero();
}
