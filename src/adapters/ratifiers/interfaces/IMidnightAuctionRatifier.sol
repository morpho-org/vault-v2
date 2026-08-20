// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Morpho Association
pragma solidity >=0.5.0;

import {Market} from "lib/midnight/src/interfaces/IMidnight.sol";
import {IRatifier} from "lib/midnight/src/interfaces/IRatifier.sol";
import {Signature} from "lib/midnight/src/ratifiers/interfaces/IEcrecoverRatifier.sol";

/// @dev Describes a Dutch auction for a reduce-only sell offer of a MidnightAdapter.
/// @dev Every Offer field is fixed by the auction except `tick`, which is free to be anything at least as good for
/// the seller as the schedule's current floor tick, linearly interpolated between (startTick, startTime) and
/// (endTick, endTime).
struct Auction {
    Market market;
    address maker;
    uint256 startTime;
    uint256 endTime;
    uint256 startTick;
    uint256 endTick;
    bytes32 group;
    address callback;
    bytes callbackData;
    address receiverIfMakerIsSeller;
    uint128 maxUnits;
    uint128 maxAssets;
    uint256 continuousFeeCap;
}

interface IMidnightAuctionRatifier is IRatifier {
    /// ERRORS ///
    error OfferMismatch();
    error BelowFloorTick();
    error InvalidAuctionWindow();
    error InvalidAuctionTicks();
    error IncorrectSigner();
}
