// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Morpho Association
pragma solidity ^0.8.0;

import "../lib/forge-std/src/Test.sol";
import {MorphoMarketV2AdapterTest} from "./MorphoMarketV2AdapterTest.sol";
import {IERC20} from "../src/interfaces/IERC20.sol";
import {MathLib} from "../src/libraries/MathLib.sol";
import {MorphoV2} from "../lib/morpho-v2/src/MorphoV2.sol";
import {Offer, Obligation} from "../lib/morpho-v2/src/interfaces/IMorphoV2.sol";
import {stdStorage, StdStorage} from "../lib/forge-std/src/Test.sol";
import {Oracle} from "../lib/morpho-v2/test/helpers/Oracle.sol";
import {Seizure} from "../lib/morpho-v2/src/interfaces/IMorphoV2.sol";

contract MorphoMarketV2AdapterAllocationUpdateTest is MorphoMarketV2AdapterTest {
    using stdStorage for StdStorage;
    using MathLib for uint256;

    address internal allocator;

    function setUp() public override {
        super.setUp();

        storedCollaterals[0].lltv = 1e18;
        storedCollaterals[1].lltv = 1e18;
        storedOffer.obligation.collaterals = storedCollaterals;

        vm.startPrank(taker);
        IERC20(storedCollaterals[0].token).approve(address(morphoV2), type(uint256).max);
        IERC20(storedCollaterals[1].token).approve(address(morphoV2), type(uint256).max);
        deal(storedCollaterals[0].token, taker, 1_000e18);
        deal(storedCollaterals[1].token, taker, 1_000e18);
        loanToken.approve(address(morphoV2), type(uint256).max);
        vm.stopPrank();
    }

    function buy(uint256 duration, uint256 assets) internal returns (Offer memory) {
        Offer memory offer = storedOffer;

        offer.obligation.maturity = block.timestamp + duration;
        offer.buy = true;
        offer.startPrice = 1e18;
        offer.expiryPrice = 1e18;
        offer.assets = assets;
        offer.expiry = block.timestamp;
        offer.callback = address(adapter);
        offer.callbackData = abi.encode(0);

        vm.startPrank(taker);
        morphoV2.supplyCollateral(offer.obligation, address(storedCollaterals[0].token), assets / 2, taker);
        morphoV2.supplyCollateral(offer.obligation, address(storedCollaterals[1].token), assets / 2, taker);
        morphoV2.take(assets, 0, 0, 0, taker, offer, proof([offer]), sign([offer], signerAllocator), address(0), "");
        vm.stopPrank();
        return offer;
    }

    function sell(Obligation memory obligation, uint256 assets) internal {
        Offer memory offer = storedOffer;

        offer.obligation = obligation;
        offer.buy = false;
        offer.startPrice = 1e18;
        offer.expiryPrice = 1e18;
        offer.assets = assets;
        offer.expiry = block.timestamp;
        offer.callback = address(adapter);
        offer.group = bytes32(vm.randomUint());
        offer.callbackData = abi.encode(0);
        vm.prank(taker);
        morphoV2.take(assets, 0, 0, 0, taker, offer, proof([offer]), sign([offer], signerAllocator), address(0), "");
    }

    function forceDeallocate(Obligation memory obligation, uint256 assets) internal {
        (address buyer, uint256 buyerPrivateKey) = makeAddrAndKey("buyer");
        privateKey[buyer] = buyerPrivateKey;

        Offer memory offer = storedOffer;
        offer.obligation = obligation;
        offer.buy = true;
        offer.maker = buyer;
        offer.startPrice = 1e18;
        offer.expiryPrice = 1e18;
        offer.assets = assets;
        offer.expiry = block.timestamp;
        offer.callback = address(0);
        offer.ratifier = address(0);
        offer.group = bytes32(vm.randomUint());

        deal(address(loanToken), buyer, assets);
        vm.prank(buyer);
        loanToken.approve(address(morphoV2), type(uint256).max);

        bytes memory data = abi.encode(offer, proof([offer]), sign([offer]));
        parentVault.forceDeallocate(address(adapter), data, assets, address(this));
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

    function testUpdateOnRealizeLoss() public {
        Offer memory offer = buy(7 days, 1e18);
        assertEq(parentVault.allocation(durationId(1 days)), 1e18, "1 week, before");
        assertEq(parentVault.allocation(durationId(7 days)), 1e18, "2 weeks, before");

        skip(1);

        Oracle(offer.obligation.collaterals[0].oracle).setPrice(0);
        morphoV2.liquidate(offer.obligation, new Seizure[](0), taker, "");
        adapter.realizeLoss(offer.obligation);

        bytes32 obligationId = _obligationId(offer.obligation);
        uint256 remainingUnits = MorphoV2(morphoV2).sharesOf(address(adapter), obligationId)
            .mulDivDown(
                MorphoV2(morphoV2).totalUnits(obligationId) + 1, MorphoV2(morphoV2).totalShares(obligationId) + 1
            );

        assertEq(parentVault.allocation(durationId(1 days)), remainingUnits, "1 day");
        assertEq(parentVault.allocation(durationId(7 days)), 0, "7 days");
    }

    function testUpdateOnWithdraw() public {
        Offer memory offer = buy(7 days, 1e18);
        assertEq(parentVault.allocation(durationId(1 days)), 1e18, "1 day, before");
        assertEq(parentVault.allocation(durationId(7 days)), 1e18, "7 days, before");

        skip(7 days);

        vm.prank(taker);
        morphoV2.repay(offer.obligation, 1e18, taker);
        vm.prank(signerAllocator);
        adapter.withdrawToVault(offer.obligation, 0.5e18, 0);

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
