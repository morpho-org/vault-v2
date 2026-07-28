// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Morpho Association
pragma solidity ^0.8.0;

import {MidnightAdapterTest} from "./MidnightAdapterTest.sol";
import {MidnightAuctionRatifier} from "../src/adapters/ratifiers/MidnightAuctionRatifier.sol";
import {IMidnightAuctionRatifier, Auction} from "../src/adapters/ratifiers/interfaces/IMidnightAuctionRatifier.sol";
import {AuctionHashLib} from "../src/adapters/ratifiers/libraries/AuctionHashLib.sol";
import {Offer, Market} from "../lib/midnight/src/interfaces/IMidnight.sol";
import {Signature, EIP712_DOMAIN_TYPEHASH} from "../lib/midnight/src/ratifiers/interfaces/IEcrecoverRatifier.sol";
import {TickLib, MAX_TICK} from "../lib/midnight/src/libraries/TickLib.sol";
import {CALLBACK_SUCCESS} from "../lib/midnight/src/libraries/ConstantsLib.sol";
import {TakeAmountsLib} from "../lib/midnight/src/periphery/TakeAmountsLib.sol";
import {IdLib} from "../lib/midnight/src/libraries/IdLib.sol";

contract MidnightAuctionRatifierTest is MidnightAdapterTest {
    MidnightAuctionRatifier internal ratifier;

    function auctionRatifierAddress() internal override returns (address) {
        ratifier = new MidnightAuctionRatifier();
        return address(ratifier);
    }

    /* HELPERS */

    function makeAuction(Market memory market, uint256 startTick, uint256 endTick, uint256 startTime, uint256 endTime)
        internal
        view
        returns (Auction memory auction)
    {
        auction.market = market;
        auction.maker = address(adapter);
        auction.startTime = startTime;
        auction.endTime = endTime;
        auction.startTick = startTick;
        auction.endTick = endTick;
        auction.group = bytes32(vm.randomUint());
        auction.callback = address(adapter);
        auction.callbackData = hex"";
        auction.receiverIfMakerIsSeller = address(adapter);
        auction.maxUnits = type(uint128).max;
        auction.maxAssets = 0;
        auction.continuousFeeCap = type(uint256).max;
    }

    function offerFromAuction(Auction memory auction, uint256 tick) internal view returns (Offer memory offer) {
        offer.market = auction.market;
        offer.buy = false;
        offer.maker = auction.maker;
        offer.start = auction.startTime;
        offer.expiry = auction.endTime;
        offer.tick = tick;
        offer.group = auction.group;
        offer.callback = auction.callback;
        offer.callbackData = auction.callbackData;
        offer.receiverIfMakerIsSeller = auction.receiverIfMakerIsSeller;
        offer.ratifier = address(ratifier);
        offer.reduceOnly = true;
        offer.maxUnits = auction.maxUnits;
        offer.maxAssets = auction.maxAssets;
        offer.continuousFeeCap = auction.continuousFeeCap;
    }

    function floorTick(Auction memory auction, uint256 timestamp) internal pure returns (uint256) {
        return auction.startTick - (auction.startTick - auction.endTick) * (timestamp - auction.startTime)
            / (auction.endTime - auction.startTime);
    }

    function signAuctionData(Auction memory auction, address signer) internal view returns (bytes memory) {
        bytes32 structHash = AuctionHashLib.hashAuction(auction);
        bytes32 domainSeparator = keccak256(abi.encode(EIP712_DOMAIN_TYPEHASH, block.chainid, address(ratifier)));
        bytes32 digest = keccak256(bytes.concat("\x19\x01", domainSeparator, structHash));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(privateKey[signer], digest);
        return abi.encode(Signature({v: v, r: r, s: s}), auction);
    }

    /* SCHEDULE VALIDATION */

    function testInvalidAuctionWindow(uint256 startTime, uint256 endTime) public {
        endTime = bound(endTime, 0, type(uint48).max - 1);
        startTime = bound(startTime, endTime, type(uint48).max);
        Auction memory auction = makeAuction(storedOffer.market, MAX_TICK, 0, startTime, endTime);
        Offer memory offer = offerFromAuction(auction, 0);
        bytes memory data = signAuctionData(auction, signerAllocator);
        vm.expectRevert(IMidnightAuctionRatifier.InvalidAuctionWindow.selector);
        ratifier.isRatified(offer, data, taker);
    }

    function testInvalidAuctionTicksEndAboveStart(uint256 startTick, uint256 endTick) public {
        startTick = bound(startTick, 0, MAX_TICK - 1);
        endTick = bound(endTick, startTick + 1, MAX_TICK);
        Auction memory auction =
            makeAuction(storedOffer.market, startTick, endTick, block.timestamp, block.timestamp + 1 days);
        Offer memory offer = offerFromAuction(auction, endTick);
        bytes memory data = signAuctionData(auction, signerAllocator);
        vm.expectRevert(IMidnightAuctionRatifier.InvalidAuctionTicks.selector);
        ratifier.isRatified(offer, data, taker);
    }

    function testInvalidAuctionTicksAboveMax(uint256 startTick) public {
        startTick = bound(startTick, MAX_TICK + 1, type(uint256).max);
        Auction memory auction =
            makeAuction(storedOffer.market, startTick, 0, block.timestamp, block.timestamp + 1 days);
        Offer memory offer = offerFromAuction(auction, 0);
        bytes memory data = signAuctionData(auction, signerAllocator);
        vm.expectRevert(IMidnightAuctionRatifier.InvalidAuctionTicks.selector);
        ratifier.isRatified(offer, data, taker);
    }

    /* TICK SCHEDULE */

    function testFloorTickAtStartTime(uint256 startTick, uint256 endTick, uint256 duration) public {
        startTick = bound(startTick, 1, MAX_TICK);
        endTick = bound(endTick, 0, startTick - 1);
        duration = bound(duration, 1, 365 days);
        Auction memory auction =
            makeAuction(storedOffer.market, startTick, endTick, block.timestamp, block.timestamp + duration);
        Offer memory offer = offerFromAuction(auction, startTick);
        bytes memory data = signAuctionData(auction, signerAllocator);
        assertEq(ratifier.isRatified(offer, data, taker), CALLBACK_SUCCESS, "at start, exactly startTick succeeds");

        offer.tick = startTick - 1;
        vm.expectRevert(IMidnightAuctionRatifier.BelowFloorTick.selector);
        ratifier.isRatified(offer, data, taker);
    }

    function testFloorTickAtEndTime(uint256 startTick, uint256 endTick, uint256 duration) public {
        startTick = bound(startTick, 1, MAX_TICK);
        endTick = bound(endTick, 0, startTick - 1);
        duration = bound(duration, 1, 365 days);
        Auction memory auction =
            makeAuction(storedOffer.market, startTick, endTick, block.timestamp, block.timestamp + duration);
        bytes memory data = signAuctionData(auction, signerAllocator);

        skip(duration);
        Offer memory offer = offerFromAuction(auction, endTick);
        assertEq(ratifier.isRatified(offer, data, taker), CALLBACK_SUCCESS, "at end, exactly endTick succeeds");

        if (endTick > 0) {
            offer.tick = endTick - 1;
            vm.expectRevert(IMidnightAuctionRatifier.BelowFloorTick.selector);
            ratifier.isRatified(offer, data, taker);
        }
    }

    function testFloorTickAtMidpoint() public {
        uint256 startTick = 6000;
        uint256 endTick = 0;
        uint256 duration = 1000;
        Auction memory auction =
            makeAuction(storedOffer.market, startTick, endTick, block.timestamp, block.timestamp + duration);
        bytes memory data = signAuctionData(auction, signerAllocator);

        skip(duration / 2);
        uint256 expectedFloor = floorTick(auction, block.timestamp);
        assertEq(expectedFloor, startTick / 2, "linear midpoint");

        Offer memory offer = offerFromAuction(auction, expectedFloor);
        assertEq(ratifier.isRatified(offer, data, taker), CALLBACK_SUCCESS, "at floor succeeds");

        offer.tick = expectedFloor - 1;
        vm.expectRevert(IMidnightAuctionRatifier.BelowFloorTick.selector);
        ratifier.isRatified(offer, data, taker);

        offer.tick = expectedFloor + 1;
        assertEq(ratifier.isRatified(offer, data, taker), CALLBACK_SUCCESS, "above floor succeeds");
    }

    /* OFFER MATCHING */

    function testOfferMismatchOnMutatedField() public {
        Auction memory auction = makeAuction(storedOffer.market, MAX_TICK, 0, block.timestamp, block.timestamp + 1 days);
        bytes memory data = signAuctionData(auction, signerAllocator);
        Offer memory offer = offerFromAuction(auction, MAX_TICK);

        // Sanity check: the untouched offer ratifies fine.
        assertEq(ratifier.isRatified(offer, data, taker), CALLBACK_SUCCESS, "untouched offer succeeds");

        Offer memory mutatedMaker = offer;
        mutatedMaker.maker = address(this);
        vm.expectRevert(IMidnightAuctionRatifier.OfferMismatch.selector);
        ratifier.isRatified(mutatedMaker, data, taker);

        Offer memory mutatedGroup = offer;
        mutatedGroup.group = bytes32(uint256(auction.group) + 1);
        vm.expectRevert(IMidnightAuctionRatifier.OfferMismatch.selector);
        ratifier.isRatified(mutatedGroup, data, taker);

        Offer memory mutatedCallback = offer;
        mutatedCallback.callback = address(this);
        vm.expectRevert(IMidnightAuctionRatifier.OfferMismatch.selector);
        ratifier.isRatified(mutatedCallback, data, taker);

        Offer memory mutatedReceiver = offer;
        mutatedReceiver.receiverIfMakerIsSeller = address(this);
        vm.expectRevert(IMidnightAuctionRatifier.OfferMismatch.selector);
        ratifier.isRatified(mutatedReceiver, data, taker);

        Offer memory mutatedBuy = offer;
        mutatedBuy.buy = true;
        vm.expectRevert(IMidnightAuctionRatifier.OfferMismatch.selector);
        ratifier.isRatified(mutatedBuy, data, taker);

        Offer memory mutatedReduceOnly = offer;
        mutatedReduceOnly.reduceOnly = false;
        vm.expectRevert(IMidnightAuctionRatifier.OfferMismatch.selector);
        ratifier.isRatified(mutatedReduceOnly, data, taker);

        Offer memory mutatedStart = offer;
        mutatedStart.start = auction.startTime + 1;
        vm.expectRevert(IMidnightAuctionRatifier.OfferMismatch.selector);
        ratifier.isRatified(mutatedStart, data, taker);

        Offer memory mutatedExpiry = offer;
        mutatedExpiry.expiry = auction.endTime - 1;
        vm.expectRevert(IMidnightAuctionRatifier.OfferMismatch.selector);
        ratifier.isRatified(mutatedExpiry, data, taker);

        Offer memory mutatedLoanToken = offer;
        mutatedLoanToken.market.loanToken = address(this);
        vm.expectRevert(IMidnightAuctionRatifier.OfferMismatch.selector);
        ratifier.isRatified(mutatedLoanToken, data, taker);
    }

    /* SIGNER VALIDATION */

    function testIncorrectSigner(uint256 seed) public {
        vm.setSeed(seed);
        (address otherSigner, uint256 otherSignerKey) = makeAddrAndKey("otherAuctionSigner");
        privateKey[otherSigner] = otherSignerKey;
        vm.assume(otherSigner != signerAllocator);

        Auction memory auction = makeAuction(storedOffer.market, MAX_TICK, 0, block.timestamp, block.timestamp + 1 days);
        Offer memory offer = offerFromAuction(auction, MAX_TICK);
        bytes memory data = signAuctionData(auction, otherSigner);
        vm.expectRevert(IMidnightAuctionRatifier.IncorrectSigner.selector);
        ratifier.isRatified(offer, data, taker);
    }

    function testSignerNotAllocator(uint256 seed) public {
        vm.setSeed(seed);
        (address nonAllocatorSigner, uint256 nonAllocatorSignerKey) = makeAddrAndKey("nonAllocatorAuctionSigner");
        privateKey[nonAllocatorSigner] = nonAllocatorSignerKey;
        assertFalse(parentVault.isAllocator(nonAllocatorSigner), "must not be allocator");

        Auction memory auction = makeAuction(storedOffer.market, MAX_TICK, 0, block.timestamp, block.timestamp + 1 days);
        Offer memory offer = offerFromAuction(auction, MAX_TICK);
        bytes memory data = signAuctionData(auction, nonAllocatorSigner);
        vm.expectRevert(IMidnightAuctionRatifier.IncorrectSigner.selector);
        ratifier.isRatified(offer, data, taker);
    }

    /* CONSTRUCTOR AUTHORIZATION */

    function testConstructorAuthorizesAuctionRatifier() public view {
        assertEq(adapter.auctionRatifier(), address(ratifier), "auctionRatifier");
        assertTrue(midnight.isAuthorized(address(adapter), address(ratifier)), "authorized at construction");
    }

    /* FULL INTEGRATION VIA MIDNIGHT.TAKE */

    function testAuctionUnwindsExistingPositionOverTime() public {
        Offer memory boughtOffer = buy(7 days, 1e18);
        bytes32 marketId = IdLib.toId(boughtOffer.market);

        uint256 startTick = TickLib.priceToTick(0.99e18, 4);
        uint256 endTick = TickLib.priceToTick(0.9e18, 4);
        uint256 duration = 1 days;
        Auction memory auction =
            makeAuction(boughtOffer.market, startTick, endTick, block.timestamp, block.timestamp + duration);

        skip(duration / 2);
        uint256 tick = floorTick(auction, block.timestamp);
        Offer memory previewOffer = offerFromAuction(auction, tick);
        auction.maxUnits =
            uint128(TakeAmountsLib.sellerAssetsToUnits(address(midnight), marketId, previewOffer, 0.1e18));
        bytes memory data = signAuctionData(auction, signerAllocator);
        Offer memory offer = offerFromAuction(auction, tick);

        parentVault.setTotalAssets(1e18);
        vm.prank(taker);
        midnight.take(offer, data, offer.maxUnits, taker, address(0), address(0), "");

        (uint128 marketNetCredit,) = adapter._markets(marketId);
        assertLt(marketNetCredit, 1e18, "position was partially unwound");
    }

    function testAuctionRevertsBelowFloorViaMidnightTake() public {
        Offer memory boughtOffer = buy(7 days, 1e18);
        bytes32 marketId = IdLib.toId(boughtOffer.market);

        uint256 startTick = TickLib.priceToTick(0.99e18, 4);
        uint256 endTick = TickLib.priceToTick(0.9e18, 4);
        uint256 duration = 1 days;
        Auction memory auction =
            makeAuction(boughtOffer.market, startTick, endTick, block.timestamp, block.timestamp + duration);

        skip(duration / 2);
        uint256 belowFloorTick = floorTick(auction, block.timestamp) - 4;
        Offer memory previewOffer = offerFromAuction(auction, belowFloorTick);
        auction.maxUnits =
            uint128(TakeAmountsLib.sellerAssetsToUnits(address(midnight), marketId, previewOffer, 0.1e18));
        bytes memory data = signAuctionData(auction, signerAllocator);
        Offer memory offer = offerFromAuction(auction, belowFloorTick);

        parentVault.setTotalAssets(1e18);
        vm.prank(taker);
        vm.expectRevert(IMidnightAuctionRatifier.BelowFloorTick.selector);
        midnight.take(offer, data, offer.maxUnits, taker, address(0), address(0), "");
    }
}
