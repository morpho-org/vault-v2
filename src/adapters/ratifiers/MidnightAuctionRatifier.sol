// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Morpho Association
pragma solidity 0.8.34;

import {Offer} from "lib/midnight/src/interfaces/IMidnight.sol";
import {MAX_TICK} from "lib/midnight/src/libraries/TickLib.sol";
import {CALLBACK_SUCCESS} from "lib/midnight/src/libraries/ConstantsLib.sol";
import {HashLib} from "lib/midnight/src/ratifiers/libraries/HashLib.sol";
import {Signature, EIP712_DOMAIN_TYPEHASH} from "lib/midnight/src/ratifiers/interfaces/IEcrecoverRatifier.sol";
import {IVaultV2} from "../../interfaces/IVaultV2.sol";
import {IMidnightAdapter} from "../interfaces/IMidnightAdapter.sol";
import {Auction, IMidnightAuctionRatifier} from "./interfaces/IMidnightAuctionRatifier.sol";
import {AuctionHashLib} from "./libraries/AuctionHashLib.sol";

/// @dev Ratifies reduce-only sell offers of a MidnightAdapter that decay linearly, in tick space, from
/// (startTick, startTime) down to (endTick, endTime).
/// @dev Stateless and generic: works for any maker that implements IMidnightAdapter's `parentVault`, so a single
/// deployment can be authorized as a ratifier by any number of MidnightAdapter instances.
contract MidnightAuctionRatifier is IMidnightAuctionRatifier {
    function isRatified(Offer memory offer, bytes memory data, address) external view returns (bytes32) {
        (Signature memory sig, Auction memory auction) = abi.decode(data, (Signature, Auction));

        require(auction.startTime < auction.endTime, InvalidAuctionWindow());
        require(auction.startTick <= MAX_TICK && auction.startTick >= auction.endTick, InvalidAuctionTicks());

        Offer memory expected = Offer({
            market: auction.market,
            buy: false,
            maker: auction.maker,
            start: auction.startTime,
            expiry: auction.endTime,
            tick: offer.tick,
            group: auction.group,
            callback: auction.callback,
            callbackData: auction.callbackData,
            receiverIfMakerIsSeller: auction.receiverIfMakerIsSeller,
            ratifier: address(this),
            reduceOnly: true,
            maxUnits: auction.maxUnits,
            maxAssets: auction.maxAssets,
            continuousFeeCap: auction.continuousFeeCap
        });
        require(HashLib.hashOffer(offer) == HashLib.hashOffer(expected), OfferMismatch());

        // Midnight's `take` already enforces startTime <= block.timestamp <= endTime before calling the ratifier.
        uint256 floorTick = auction.startTick - (auction.startTick - auction.endTick)
            * (block.timestamp - auction.startTime) / (auction.endTime - auction.startTime);
        require(offer.tick >= floorTick, BelowFloorTick());

        bytes32 structHash = AuctionHashLib.hashAuction(auction);
        bytes32 domainSeparator = keccak256(abi.encode(EIP712_DOMAIN_TYPEHASH, block.chainid, address(this)));
        bytes32 digest = keccak256(bytes.concat("\x19\x01", domainSeparator, structHash));
        address signer = ecrecover(digest, sig.v, sig.r, sig.s);
        require(signer != address(0), IncorrectSigner());
        require(IVaultV2(IMidnightAdapter(auction.maker).parentVault()).isAllocator(signer), IncorrectSigner());

        return CALLBACK_SUCCESS;
    }
}
