// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

library ErrorsLib {
    error Unauthorized();
    error Locked();
    error FailedDelegateCall();
    error TimelockNotExpired();
    error WrongTimelockDuration();
    error WrongTimelockValue();
    error CapExceeded();
}
