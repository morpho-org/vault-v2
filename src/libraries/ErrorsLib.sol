// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

library ErrorsLib {
    error CastOverflow();
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
    error FeeInvariantBroken();
    error PermitDeadlineExpired();
    error InvalidSigner();
    error LiquidityAdapterInvariantBroken();
    error ApproveReverted();
    error ApproveReturnedFalse();
    error InfiniteTimelock();
    error CannotSend();
    error CannotReceive();
    error CannotSendUnderlyingAssets();
    error CannotReceiveUnderlyingAssets();
    error EnterBlocked();
    error IdNotEnabled();
    error AdapterId();
}
