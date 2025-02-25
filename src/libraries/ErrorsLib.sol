// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

library ErrorsLib {
    error Unauthorized();
    error Locked();
    error FailedDelegateCall();
    error TimelockIsChanging();
    error TimelockNotExpired();
    error TimelockNotSet();
    error TimelockPending();
    error TimelockTooSmall();
    error WrongValue();
    error CapExceeded();
}
