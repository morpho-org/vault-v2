// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

library ErrorsLib {
    error NoCode();
    error TransferReverted();
    error TransferReturnedFalse();
    error TransferFromReverted();
    error TransferFromReturnedFalse();
    error FeeTooHigh();
    error ZeroAddress();
    error Unauthorized();
    error TimelockCapIsFixed();
    error TimelockDurationTooHigh();
    error WrongPendingValue();
    error CapExceeded();
    error DataAlreadyPending();
    error TimelockNotIncreasing();
    error TimelockNotDecreasing();
    error InvalidRole();
    error AbsoluteCapExceeded();
    error RelativeCapExceeded();
    error IdNotFound();
    error NotAllocator();
    error NotAdapter();
    error FeeInvariantBroken();
    error InvalidRate();
    error PermitDeadlineExpired();
    error InvalidSigner();
}
