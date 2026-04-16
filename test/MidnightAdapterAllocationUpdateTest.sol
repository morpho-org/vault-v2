// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Morpho Association
pragma solidity ^0.8.0;

import "../lib/forge-std/src/Test.sol";
import {MidnightAdapterTest} from "./MidnightAdapterTest.sol";
import {IERC20} from "../src/interfaces/IERC20.sol";
import {MathLib} from "../src/libraries/MathLib.sol";
import {Offer, Obligation, CollateralParams} from "../lib/midnight/src/interfaces/IMidnight.sol";
import {TickLib, MAX_TICK} from "../lib/midnight/src/libraries/TickLib.sol";
import {stdStorage, StdStorage} from "../lib/forge-std/src/Test.sol";
import {Oracle} from "../lib/midnight/test/helpers/Oracle.sol";
import {SetterRatifier} from "../lib/midnight/src/ratifiers/SetterRatifier.sol";

contract MidnightAdapterAllocationUpdateTest is MidnightAdapterTest {
    using stdStorage for StdStorage;
    using MathLib for uint256;

    address internal allocator;

    function setUp() public override {
        super.setUp();

        storedCollaterals[0].lltv = 1e18;
        storedCollaterals[0].maxLif = midnight.maxLif(1e18, 0.25e18);
        storedCollaterals[1].lltv = 1e18;
        storedCollaterals[1].maxLif = midnight.maxLif(1e18, 0.25e18);
        storedOffer.obligation.collateralParams = storedCollaterals;

        vm.startPrank(taker);
        IERC20(storedCollaterals[0].token).approve(address(midnight), type(uint256).max);
        IERC20(storedCollaterals[1].token).approve(address(midnight), type(uint256).max);
        deal(storedCollaterals[0].token, taker, 1_000e18);
        deal(storedCollaterals[1].token, taker, 1_000e18);
        loanToken.approve(address(midnight), type(uint256).max);
        vm.stopPrank();
    }

    function buy(uint256 duration, uint256 assets) internal returns (Offer memory) {
        Offer memory offer = storedOffer;

        offer.obligation.maturity = block.timestamp + duration;
        offer.buy = true;
        offer.tick = MAX_TICK;
        uint256 price = TickLib.tickToPrice(MAX_TICK);
        uint256 units = assets * 1e18 / price;
        offer.maxUnits = units;
        offer.expiry = block.timestamp;
        offer.callback = address(adapter);
        offer.callbackData = abi.encode(0);

        vm.startPrank(taker);
        midnight.supplyCollateral(offer.obligation, 0, assets / 2, taker);
        midnight.supplyCollateral(offer.obligation, 1, assets / 2, taker);
        midnight.take(
            units, taker, address(0), "", taker, offer, sign([offer], signerAllocator), root([offer]), proof([offer])
        );
        vm.stopPrank();
        return offer;
    }

    function sell(Obligation memory obligation, uint256 assets) internal {
        Offer memory offer = storedOffer;

        offer.obligation = obligation;
        offer.buy = false;
        offer.reduceOnly = true;
        offer.tick = MAX_TICK;
        uint256 price = TickLib.tickToPrice(MAX_TICK);
        uint256 units = assets * 1e18 / price;
        offer.maxUnits = units;
        offer.expiry = block.timestamp;
        offer.callback = address(adapter);
        offer.receiverIfMakerIsSeller = address(adapter);
        offer.group = bytes32(vm.randomUint());
        offer.callbackData = abi.encode(0);
        vm.prank(taker);
        midnight.take(
            units, taker, address(0), "", taker, offer, sign([offer], signerAllocator), root([offer]), proof([offer])
        );
    }

    function forceDeallocate(Obligation memory obligation, uint256 assets) internal {
        deal(address(loanToken), address(adapter), assets);
        parentVault.forceDeallocate(address(adapter), abi.encode(obligation), assets, address(this));
    }

    function durationId(uint256 duration) internal pure returns (bytes32) {
        return keccak256(abi.encode("duration", duration));
    }

    function testExactDuration(uint32 durationIndex) public {
        durationIndex = uint32(bound(durationIndex, 0, adapter.durationsLength() - 1));
        uint256 duration = adapter.durations()[durationIndex];
        buy(duration, 1e18);
        assertEq(parentVault.allocation(durationId(duration)), 1e18);
    }

    function testExitDuration(uint256 durationIndex, uint256 timeToMaturity, uint256 extraSkip) public {
        durationIndex = bound(durationIndex, 0, adapter.durationsLength() - 1);
        uint256 duration = adapter.durations()[durationIndex];
        timeToMaturity = bound(timeToMaturity, duration, type(uint32).max);
        extraSkip = bound(extraSkip, 1, 10 * 365 days);

        Offer memory offer = buy(timeToMaturity, 1e18);
        assertEq(parentVault.allocation(durationId(duration)), 1e18);

        skip(timeToMaturity - duration + extraSkip);

        adapter.deallocateExpiredDurations(offer.obligation);

        assertEq(parentVault.allocation(durationId(duration)), 0);
    }

    function testRepeatDeallocateExpiredDurations(uint256 durationIndex, uint256 timeToMaturity, uint256 skipAmount)
        public
    {
        durationIndex = bound(durationIndex, 0, adapter.durationsLength() - 1);
        uint256 duration = adapter.durations()[durationIndex];
        timeToMaturity = bound(timeToMaturity, duration, type(uint32).max);
        skipAmount = bound(skipAmount, 0, duration * 2);

        Offer memory offer = buy(timeToMaturity, 1e18);
        skip(skipAmount);
        adapter.deallocateExpiredDurations(offer.obligation);
        uint256 savedAllocation = parentVault.allocation(durationId(duration));
        adapter.deallocateExpiredDurations(offer.obligation);
        assertEq(parentVault.allocation(durationId(duration)), savedAllocation);
    }

    function testUpdateOnWithdraw() public {
        Offer memory offer = buy(7 days, 1e18);
        assertEq(parentVault.allocation(durationId(1 days)), 1e18, "1 day, before");
        assertEq(parentVault.allocation(durationId(7 days)), 1e18, "7 days, before");

        skip(7 days);

        vm.prank(taker);
        midnight.repay(offer.obligation, 1e18, taker, "");
        vm.prank(signerAllocator);
        adapter.withdrawToVault(offer.obligation, 0.5e18);

        assertEq(parentVault.allocation(durationId(1 days)), 0, "1 day");
        assertEq(parentVault.allocation(durationId(7 days)), 0, "7 days");
    }

    function testUpdateOnSell() public {
        Offer memory offer = buy(7 days, 1e18);
        assertEq(parentVault.allocation(durationId(1 days)), 1e18, "1 day, before");
        assertEq(parentVault.allocation(durationId(7 days)), 1e18, "7 days, before");

        skip(1);

        parentVault.setTotalAssets(1e18);
        parentVault.setAdaptersLength(1);
        address[] memory adapters = new address[](1);
        adapters[0] = address(adapter);
        parentVault.setAdapters(adapters);
        sell(offer.obligation, 0.5e18);

        assertEq(parentVault.allocation(durationId(1 days)), 0.5e18, "1 day");
        assertEq(parentVault.allocation(durationId(7 days)), 0, "7 days");
    }

    function testUpdateOnForceDeallocate() public {
        Offer memory offer = buy(7 days, 1e18);
        assertEq(parentVault.allocation(durationId(1 days)), 1e18, "1 day, before");
        assertEq(parentVault.allocation(durationId(7 days)), 1e18, "7 days, before");

        skip(1);

        forceDeallocate(offer.obligation, 0.5e18);

        assertEq(parentVault.allocation(durationId(1 days)), 0.5e18, "1 day");
        assertEq(parentVault.allocation(durationId(7 days)), 0, "7 days");
    }
}
