// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

library ErrorsLib {
    error FeeTooHigh();
    error ExitFeeTooHigh();
    error ZeroAddress();
    error Unauthorized();
    error Locked();
    error FailedDelegateCall();
    error CantSet();
    error TimelockNotExpired();
    error TimelockCapIsFixed();
    error TimelockDurationTooHigh();
    error WrongPendingValue();
    error CapExceeded();
}
