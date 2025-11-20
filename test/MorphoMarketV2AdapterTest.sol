// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Morpho Association
pragma solidity ^0.8.0;

import "../lib/forge-std/src/Test.sol";
import {MorphoMarketV2Adapter, Maturity, ObligationPosition} from "../src/adapters/MorphoMarketV2Adapter.sol";
import {MorphoMarketV2AdapterFactory} from "../src/adapters/MorphoMarketV2AdapterFactory.sol";
import {ERC20Mock} from "./mocks/ERC20Mock.sol";
import {OracleMock} from "../lib/morpho-blue/src/mocks/OracleMock.sol";
import {VaultV2Mock} from "./mocks/VaultV2Mock.sol";
import {IERC20} from "../src/interfaces/IERC20.sol";
import {IVaultV2} from "../src/interfaces/IVaultV2.sol";
import {IMorphoMarketV2Adapter} from "../src/adapters/interfaces/IMorphoMarketV2Adapter.sol";
import {IMorphoMarketV2AdapterFactory} from "../src/adapters/interfaces/IMorphoMarketV2AdapterFactory.sol";
import {MathLib} from "../src/libraries/MathLib.sol";
import {MathLib as MorphoV2MathLib} from "lib/morpho-v2/src/libraries/MathLib.sol";
import {MorphoV2} from "../lib/morpho-v2/src/MorphoV2.sol";
import {Offer, Signature, Obligation, Collateral, Proof} from "../lib/morpho-v2/src/interfaces/IMorphoV2.sol";
import {stdStorage, StdStorage} from "../lib/forge-std/src/Test.sol";
import {stdError} from "../lib/forge-std/src/StdError.sol";
import {ORACLE_PRICE_SCALE} from "../lib/morpho-blue/src/libraries/ConstantsLib.sol";
import {DurationsLib, MAX_DURATIONS} from "../src/adapters/libraries/DurationsLib.sol";

struct Step {
    uint256 assets;
    uint256 approxGrowth;
    uint256 maturity;
    Collateral[] collaterals;
}

contract MorphoMarketV2AdapterTest is Test {
    using stdStorage for StdStorage;
    using MathLib for uint256;

    MorphoV2 internal morphoV2;
    IMorphoMarketV2AdapterFactory internal factory;
    IMorphoMarketV2Adapter internal adapter;
    VaultV2Mock internal parentVault;
    IERC20 internal loanToken;
    IERC20 internal rewardToken;
    address internal owner;
    address internal curator;
    address internal signerAllocator;
    uint256 internal signerAllocatorPrivateKey;
    address internal taker;
    address internal recipient;
    address internal tradingFeeRecipient = makeAddr("tradingFeeRecipient");
    Collateral[] internal storedCollaterals;
    Collateral[] internal storedSingleCollateral;

    mapping(address => uint256) internal privateKey;

    Offer storedOffer;

    uint256 internal constant MIN_TEST_ASSETS = 10;
    uint256 internal constant MAX_TEST_ASSETS = 1e24;

    // Hardcoded obligation setups
    Step[] internal steps00;
    Step[] internal steps01;

    // Expected values after setting up obligations
    mapping(bytes32 obligationId => ObligationPosition) expectedPositions;
    mapping(uint256 timestamp => uint256) expectedMaturityGrowths;
    uint256[] internal expectedPositionsList;
    uint256[] internal expectedMaturitiesList;
    uint256 internal expectedAddedGrowth;
    uint256 internal expectedAddedAssets;

    function setUp() public {
        owner = makeAddr("owner");
        curator = makeAddr("curator");
        (signerAllocator, signerAllocatorPrivateKey) = makeAddrAndKey("signerAllocator");
        privateKey[signerAllocator] = signerAllocatorPrivateKey;

        recipient = makeAddr("recipient");
        taker = makeAddr("taker");

        morphoV2 = new MorphoV2();

        vm.prank(morphoV2.owner());
        morphoV2.setTradingFeeRecipient(tradingFeeRecipient);

        loanToken = IERC20(address(new ERC20Mock(18)));
        rewardToken = IERC20(address(new ERC20Mock(18)));

        parentVault = new VaultV2Mock(address(loanToken), owner, curator, signerAllocator, address(0));

        factory = new MorphoMarketV2AdapterFactory();
        adapter = MorphoMarketV2Adapter(factory.createMorphoMarketV2Adapter(address(parentVault), address(morphoV2)));

        storedCollaterals.push(
            Collateral({token: address(new ERC20Mock(18)), lltv: 0.8 ether, oracle: address(new OracleMock())})
        );
        storedCollaterals.push(
            Collateral({token: address(new ERC20Mock(18)), lltv: 0.9 ether, oracle: address(new OracleMock())})
        );

        OracleMock(storedCollaterals[0].oracle).setPrice(ORACLE_PRICE_SCALE);
        OracleMock(storedCollaterals[1].oracle).setPrice(ORACLE_PRICE_SCALE);

        storedSingleCollateral.push(storedCollaterals[0]);

        uint256 maturity = vm.getBlockTimestamp() + 200;
        uint256 rate = 0.05e18;
        storedOffer = Offer({
            buy: true,
            maker: address(adapter),
            assets: 100,
            obligationUnits: 0,
            obligationShares: 0,
            obligation: Obligation({
                chainId: block.chainid,
                loanToken: address(loanToken),
                collaterals: storedCollaterals,
                maturity: maturity
            }),
            start: vm.getBlockTimestamp(),
            expiry: maturity,
            startPrice: 1e36 / (1e18 + rate * (maturity - vm.getBlockTimestamp()) / 365 days),
            expiryPrice: 1e18,
            group: bytes32(0),
            session: bytes32(0),
            ratifier: address(adapter),
            callback: address(adapter),
            callbackData: bytes("")
        });

        deal(address(loanToken), address(parentVault), 1_000_000e18);

        // steps00 is empty

        // 1.5e15 is ~1M dai lent at 5%/yr
        steps01.push(
            Step({
                assets: 100, approxGrowth: 1.5e15, maturity: vm.getBlockTimestamp() + 1, collaterals: storedCollaterals
            })
        );
        steps01.push(
            Step({
                assets: 100, approxGrowth: 2e15, maturity: vm.getBlockTimestamp() + 100, collaterals: storedCollaterals
            })
        );
        steps01.push(
            Step({
                assets: 100, approxGrowth: 1e15, maturity: vm.getBlockTimestamp() + 200, collaterals: storedCollaterals
            })
        );
        steps01.push(
            Step({
                assets: 100, approxGrowth: 1e15, maturity: vm.getBlockTimestamp() + 200, collaterals: storedCollaterals
            })
        );
        steps01.push(
            Step({
                assets: 100,
                approxGrowth: 1e15,
                maturity: vm.getBlockTimestamp() + 200,
                collaterals: storedSingleCollateral
            })
        );
    }

    function testSimpleBuy() public {
        Offer memory offer = storedOffer;

        vm.startPrank(taker);
        IERC20(storedCollaterals[0].token).approve(address(morphoV2), type(uint256).max);
        IERC20(storedCollaterals[1].token).approve(address(morphoV2), type(uint256).max);
        deal(storedCollaterals[0].token, taker, 1_000e18);
        deal(storedCollaterals[1].token, taker, 1_000e18);
        morphoV2.supplyCollateral(offer.obligation, address(storedCollaterals[0].token), 1_000e18, taker);
        morphoV2.supplyCollateral(offer.obligation, address(storedCollaterals[1].token), 1_000e18, taker);
        vm.stopPrank();

        uint256 assets = 1e18;

        offer.assets = 1e18;
        offer.callback = address(adapter);
        offer.callbackData = abi.encode(0);
        vm.prank(taker);
        morphoV2.take(assets, 0, 0, 0, taker, offer, proof([offer]), sign([offer], signerAllocator), address(0), "");

        uint256 units = assets * 1e18 / offer.startPrice;
        uint256 remainder = (units - assets) % (offer.obligation.maturity - vm.getBlockTimestamp());
        assertEq(adapter._totalAssets(), assets + remainder, "_totalAssets");
        assertEq(adapter.lastUpdate(), vm.getBlockTimestamp(), "lastUpdate");
        assertEq(adapter.firstMaturity(), vm.getBlockTimestamp() + 200, "firstMaturity");

        uint256 totalInterest = assets * 1e18 / offer.startPrice - assets;
        uint256 duration = offer.obligation.maturity - vm.getBlockTimestamp();
        uint256 newGrowth = totalInterest / duration;
        assertEq(adapter.currentGrowth(), newGrowth, "currentGrowth");
        Maturity memory maturity = adapter.maturities(offer.obligation.maturity);
        assertEq(maturity.growthLostAtMaturity, newGrowth, "growthLostAtMaturity");
        assertEq(maturity.nextMaturity, type(uint48).max, "nextMaturity");

        ObligationPosition memory position = adapter.positions(_obligationId(offer.obligation));
        assertEq(position.growth, newGrowth, "growth");
        assertEq(position.units, assets + totalInterest, "units");
    }

    /* RATIFICATION */

    function _ratificationSetup() internal returns (Offer memory offer) {
        offer.buy = true;
        offer.maker = address(adapter);
        offer.assets = 100;

        offer.obligation.chainId = block.chainid;
        offer.obligation.loanToken = address(loanToken);
        uint256 numCollaterals = bound(vm.randomUint(), 0, 3);
        Collateral[] memory collaterals = new Collateral[](numCollaterals);
        for (uint256 i = 0; i < numCollaterals; i++) {
            collaterals[i] =
                Collateral({token: address(new ERC20Mock(18)), lltv: 0.8 ether, oracle: address(new OracleMock())});
        }
        offer.obligation.collaterals = collaterals;
        offer.obligation.maturity = bound(vm.randomUint(), vm.getBlockTimestamp(), type(uint48).max);

        offer.start = bound(vm.randomUint(), 0, vm.getBlockTimestamp());
        offer.expiry = bound(vm.randomUint(), offer.start, type(uint48).max);
        offer.startPrice = bound(vm.randomUint(), 1, 1e18);
        if (offer.expiry > offer.start) {
            offer.expiryPrice = bound(vm.randomUint(), offer.startPrice, 1e18);
        }
        offer.callback = address(adapter);
        offer.callbackData = bytes("");
    }

    function testRatifyIncorrectOfferBadSellSigner(uint256 seed, address otherSigner) public {
        vm.setSeed(seed);
        vm.assume(otherSigner != signerAllocator);
        Offer memory offer = _ratificationSetup();
        vm.expectRevert(IMorphoMarketV2Adapter.IncorrectSigner.selector);
        vm.prank(address(morphoV2));
        adapter.onRatify(offer, otherSigner);
    }

    function testRatifyIncorrectOfferBadBuySigner(uint256 seed, address otherSigner) public {
        vm.setSeed(seed);
        vm.assume(otherSigner != signerAllocator);
        vm.assume(otherSigner != address(adapter));
        Offer memory offer = _ratificationSetup();
        vm.expectRevert(IMorphoMarketV2Adapter.IncorrectSigner.selector);
        vm.prank(address(morphoV2));
        adapter.onRatify(offer, otherSigner);
    }

    function testRatifyLoanAssetMismatch(uint256 seed, address otherToken) public {
        vm.setSeed(seed);
        Offer memory offer = _ratificationSetup();
        vm.assume(otherToken != offer.obligation.loanToken);
        offer.obligation.loanToken = otherToken;
        vm.expectRevert(IMorphoMarketV2Adapter.LoanAssetMismatch.selector);
        vm.prank(address(morphoV2));
        adapter.onRatify(offer, signerAllocator);
    }

    function testRatifyIncorrectOwner(uint256 seed, address otherMaker) public {
        vm.setSeed(seed);
        Offer memory offer = _ratificationSetup();
        vm.assume(otherMaker != address(adapter));
        offer.maker = otherMaker;
        vm.expectRevert(IMorphoMarketV2Adapter.IncorrectOwner.selector);
        vm.prank(address(morphoV2));
        adapter.onRatify(offer, signerAllocator);
    }

    function testRatifyIncorrectMaturity(uint256 seed) public {
        vm.setSeed(seed);
        Offer memory offer = _ratificationSetup();
        offer.obligation.maturity = vm.randomUint(type(uint48).max, type(uint256).max);
        vm.expectRevert(IMorphoMarketV2Adapter.IncorrectMaturity.selector);
        vm.prank(address(morphoV2));
        adapter.onRatify(offer, signerAllocator);
    }

    function testRatifyIncorrectStart(uint256 seed) public {
        vm.setSeed(seed);
        Offer memory offer = _ratificationSetup();
        offer.start = vm.getBlockTimestamp() + 1;
        vm.expectRevert(IMorphoMarketV2Adapter.IncorrectStart.selector);
        vm.prank(address(morphoV2));
        adapter.onRatify(offer, signerAllocator);
    }

    function testRatifyIncorrectCallbackAddress(uint256 seed) public {
        vm.setSeed(seed);
        Offer memory offer = _ratificationSetup();
        offer.callback = address(0);
        vm.expectRevert(IMorphoMarketV2Adapter.IncorrectCallbackAddress.selector);
        vm.prank(address(morphoV2));
        adapter.onRatify(offer, signerAllocator);
    }

    function testRatifyIncorrectExpiry(uint256 seed) public {
        vm.setSeed(seed);
        Offer memory offer = _ratificationSetup();
        vm.prank(address(morphoV2));
        adapter.onRatify(offer, signerAllocator);
    }

    /* STEPS SETUP */

    function setupObligations(Step[] memory steps) internal {
        vm.startPrank(taker);
        IERC20(storedCollaterals[0].token).approve(address(morphoV2), type(uint256).max);
        IERC20(storedCollaterals[1].token).approve(address(morphoV2), type(uint256).max);
        vm.stopPrank();

        Offer memory offer = Offer({
            buy: true,
            maker: address(adapter),
            start: vm.getBlockTimestamp(),
            expiry: vm.getBlockTimestamp() + 1,
            expiryPrice: 1e18,
            callback: address(adapter),
            callbackData: abi.encode(0),
            obligation: Obligation({
                chainId: block.chainid,
                loanToken: address(loanToken),
                collaterals: storedCollaterals,
                // will be adjusted in loop
                maturity: 0
            }),
            // will be adjusted in loop
            startPrice: 0,
            assets: 0,
            obligationUnits: 0,
            obligationShares: 0,
            group: bytes32(0),
            session: bytes32(0),
            ratifier: address(adapter)
        });

        for (uint256 i = 0; i < steps.length; i++) {
            Step memory step = steps[i];
            uint256 timeToMaturity = step.maturity - vm.getBlockTimestamp();
            require(timeToMaturity > 0 || step.approxGrowth == 0, "nonzero growth on 0 duration");
            uint256 approxInterest = step.approxGrowth * timeToMaturity;
            offer.group = bytes32(i);
            offer.assets = step.assets;
            offer.obligation.maturity = step.maturity;
            offer.startPrice = step.assets.mulDivDown(1e18, step.assets + approxInterest);
            uint256 units = step.assets.mulDivDown(1e18, offer.startPrice);
            uint256 actualGrowth = (units - offer.assets) / timeToMaturity;
            uint256 zeroPeriodGain = (units - offer.assets) % timeToMaturity;
            // uint actualInterest = actualGrowth * timeToMaturity;
            bytes32 obligationId = _obligationId(offer.obligation);

            vm.startPrank(taker);
            deal(storedCollaterals[0].token, taker, 1_000e18);
            deal(storedCollaterals[1].token, taker, 1_000e18);
            morphoV2.supplyCollateral(offer.obligation, address(storedCollaterals[0].token), 1_000e18, taker);
            morphoV2.supplyCollateral(offer.obligation, address(storedCollaterals[1].token), 1_000e18, taker);

            ObligationPosition memory positionBefore = adapter.positions(obligationId);
            morphoV2.take(
                step.assets, 0, 0, 0, taker, offer, proof([offer]), sign([offer], signerAllocator), address(0), ""
            );
            vm.stopPrank();

            assertEq(adapter.positions(obligationId).units, positionBefore.units + units, "setup: units 1");

            expectedPositions[obligationId].units += units.toUint128();
            expectedPositions[obligationId].growth += actualGrowth.toUint128();
            if (timeToMaturity > 0) {
                expectedMaturityGrowths[step.maturity] += actualGrowth.toUint128();
                expectedAddedGrowth += actualGrowth.toUint128();
            }
            expectedAddedAssets += step.assets + zeroPeriodGain;
            expectedPositionsList.push(uint256(obligationId));
            expectedMaturitiesList.push(step.maturity);
        }
        expectedPositionsList = removeCopies(expectedPositionsList);
        expectedMaturitiesList = removeCopies(expectedMaturitiesList);
    }

    // Apply steps in random order and test that the effect on the state is correct.
    // TODO when building a list must move forward in time so that coverage is complete
    function stepsSetupTest(Step[] storage steps) internal {
        uint256[] memory indices = new uint256[](steps.length);
        for (uint256 i = 0; i < steps.length; i++) {
            indices[i] = i;
        }
        indices = vm.shuffle(indices);

        setupObligations(steps);

        // Check pointer to first element of maturities list
        if (steps.length > 0) {
            assertEq(adapter.firstMaturity(), steps[0].maturity, "firstMaturity");
        } else {
            assertEq(adapter.firstMaturity(), type(uint48).max, "firstMaturity");
        }

        // Check maturities growth and linked list structure
        for (uint256 i = 0; i < expectedMaturitiesList.length; i++) {
            assertEq(
                adapter.maturities(expectedMaturitiesList[i]).growthLostAtMaturity,
                expectedMaturityGrowths[expectedMaturitiesList[i]],
                "growthLostAtMaturity"
            );
            if (i == expectedMaturitiesList.length - 1) {
                assertEq(
                    adapter.maturities(expectedMaturitiesList[i]).nextMaturity, type(uint48).max, "nextMaturity end"
                );
            } else {
                assertEq(
                    adapter.maturities(expectedMaturitiesList[i]).nextMaturity,
                    expectedMaturitiesList[i + 1],
                    "nextMaturity middle"
                );
            }
        }

        // Check positions growth and size
        for (uint256 i = 0; i < expectedPositionsList.length; i++) {
            bytes32 obligationId = bytes32(expectedPositionsList[i]);
            ObligationPosition memory position = adapter.positions(obligationId);
            ObligationPosition memory expectedPosition = expectedPositions[obligationId];
            assertEq(position.growth, expectedPosition.growth, "growth");
            assertEq(position.units, expectedPosition.units, "units");
        }
    }

    function testStepsSetup00(uint256 seed) public {
        vm.setSeed(seed);
        stepsSetupTest(steps00);
    }

    function testStepsSetup01(uint256 seed) public {
        vm.setSeed(seed);
        stepsSetupTest(steps01);
    }

    /* ACCRUE INTEREST USING STEPS */

    // Apply steps and test that accrueInterestView over time is correct.
    function accrueInterestViewTest(Step[] memory steps, uint256 initialGrowth, uint256 _totalAssets, uint256 elapsed)
        internal
    {
        uint256 begin = vm.getBlockTimestamp();
        initialGrowth = bound(initialGrowth, 0, 1e36);
        _totalAssets = bound(_totalAssets, 0, type(uint128).max);
        uint256 maxElapsed =
            steps.length == 0 ? 365 days : 2 * (steps[steps.length - 1].maturity - vm.getBlockTimestamp());
        elapsed = bound(elapsed, 0, maxElapsed);

        setCurrentGrowth(uint128(initialGrowth));
        set_TotalAssets(_totalAssets);
        setupObligations(steps);
        uint256 expectedCurrentGrowth = initialGrowth + expectedAddedGrowth;
        assertEq(adapter.currentGrowth(), expectedCurrentGrowth, "currentGrowth");
        assertEq(adapter._totalAssets(), _totalAssets + expectedAddedAssets, "_totalAssets");

        skip(elapsed);

        (uint48 nextMaturity, uint128 newGrowth, uint256 newTotalAssets) = adapter.accrueInterestView();

        uint256 lostGrowth = 0;
        uint256 interest = initialGrowth * elapsed;
        uint256 expectedNextMaturity = type(uint48).max;

        for (uint256 i = 0; i < expectedMaturitiesList.length; i++) {
            uint256 maturity = expectedMaturitiesList[i];
            if (maturity < vm.getBlockTimestamp()) {
                lostGrowth += expectedMaturityGrowths[maturity];
                interest += expectedMaturityGrowths[maturity] * (maturity - begin);
            } else {
                interest += expectedMaturityGrowths[maturity] * elapsed;
            }
            if (maturity >= vm.getBlockTimestamp() && maturity < expectedNextMaturity) {
                expectedNextMaturity = maturity;
            }
        }
        assertEq(nextMaturity, expectedNextMaturity, "nextMaturity");
        assertEq(newGrowth, expectedCurrentGrowth - lostGrowth, "newGrowth");
        assertEq(newTotalAssets, _totalAssets + expectedAddedAssets + interest, "newTotalAssets");
    }

    function testAccrueInterestView00(uint256 growth, uint256 _totalAssets, uint256 elapsed) public {
        accrueInterestViewTest(steps00, growth, _totalAssets, elapsed);
    }

    function testAccrueInterestView01(uint256 growth, uint256 _totalAssets, uint256 elapsed) public {
        accrueInterestViewTest(steps01, growth, _totalAssets, elapsed);
    }

    /* DURATIONS */

    function testDurationsUpdate() public {
        vm.startPrank(parentVault.curator());
        vm.expectEmit();
        emit IMorphoMarketV2Adapter.AddDuration(10);
        adapter.addDuration(10);
        assertEq(adapter.durations().length, 1);
        assertEq(adapter.durations(), [uint256(10)]);

        vm.expectEmit();
        emit IMorphoMarketV2Adapter.RemoveDuration(10);
        adapter.removeDuration(10);
        assertEq(adapter.durations().length, 0);

        vm.expectEmit();
        emit IMorphoMarketV2Adapter.AddDuration(20);
        adapter.addDuration(20);
        assertEq(adapter.durations().length, 1);
        assertEq(adapter.durations()[0], 20);

        vm.expectEmit();
        emit IMorphoMarketV2Adapter.AddDuration(1);
        adapter.addDuration(1);
        assertEq(adapter.durations().length, 2);
        assertEq(adapter.durations()[0], 20);
        assertEq(adapter.durations()[1], 1);

        vm.expectEmit();
        emit IMorphoMarketV2Adapter.RemoveDuration(20);
        adapter.removeDuration(20);
        assertEq(adapter.durations().length, 1);

        adapter.addDuration(19);
        adapter.addDuration(20);
        adapter.addDuration(99);
        adapter.addDuration(98);
        adapter.addDuration(97);
        adapter.addDuration(96);
        adapter.addDuration(95);
        assertEq(adapter.durations().length, 8);
        assertEq(adapter.durations()[0], 19);
        assertEq(adapter.durations()[1], 1);
        assertEq(adapter.durations()[2], 20);
        assertEq(adapter.durations()[3], 99);
        assertEq(adapter.durations()[4], 98);
        assertEq(adapter.durations()[5], 97);
        assertEq(adapter.durations()[6], 96);
        assertEq(adapter.durations()[7], 95);
        adapter.removeDuration(95);
        assertEq(adapter.durations().length, 7);
        adapter.addDuration(94);
        vm.expectRevert(IMorphoMarketV2Adapter.MaxDurationsExceeded.selector);
        adapter.addDuration(2);
        vm.stopPrank();
    }

    function testSetDurationsAccess(address sender, uint256 duration) public {
        vm.assume(sender != parentVault.curator());
        vm.prank(sender);
        vm.expectRevert(IMorphoMarketV2Adapter.NotAuthorized.selector);
        adapter.addDuration(duration);

        vm.prank(sender);
        vm.expectRevert(IMorphoMarketV2Adapter.NotAuthorized.selector);
        adapter.removeDuration(duration);
    }

    function testAddDurationIncorrectOrDuplicate(bytes32 _durations, uint256 duplicated) public {
        vm.assume(uint256(_durations) > type(uint16).max);
        set_Durations(_durations);
        uint256[] memory durationsArray = adapter.durations();
        duplicated = bound(duplicated, 0, durationsArray.length - 1);
        if (durationsArray[duplicated] == 0 || durationsArray[duplicated] > type(uint32).max) {
            vm.prank(parentVault.curator());
            vm.expectRevert(IMorphoMarketV2Adapter.IncorrectDuration.selector);
            adapter.addDuration(durationsArray[duplicated]);
        } else {
            vm.prank(parentVault.curator());
            vm.expectRevert(IMorphoMarketV2Adapter.NoDuplicates.selector);
            adapter.addDuration(durationsArray[duplicated]);
        }
    }

    function testDurationsGetter(bytes32 _durations) public {
        set_Durations(_durations);
        uint256[] memory durationsArray = adapter.durations();
        uint256 arrayIndex = 0;
        for (uint256 i = 0; i < MAX_DURATIONS; i++) {
            uint256 duration = uint256(uint32(bytes4(_durations << (32 * i))));
            if (duration != 0) assertEq(durationsArray[arrayIndex++], duration);
        }
    }

    /* IDS */

    function testIds(uint256 collateralCount, uint256 durationsCount, uint256 maturity) public {
        uint256[] memory possibleDurations = new uint256[](4);
        possibleDurations[0] = 1 days;
        possibleDurations[1] = 10 days;
        possibleDurations[2] = 300 days;
        possibleDurations[3] = 700 days;
        possibleDurations = vm.shuffle(possibleDurations);

        collateralCount = bound(collateralCount, 0, 5);
        durationsCount = bound(durationsCount, 0, 4);

        Obligation memory obligation;

        Collateral[] memory collaterals = new Collateral[](collateralCount);
        for (uint256 i = 0; i < collateralCount; i++) {
            collaterals[i].token = address(uint160(i));
        }
        obligation.collaterals = storedCollaterals;
        obligation.maturity = bound(maturity, 1, 700 days);
        vm.startPrank(parentVault.curator());
        for (uint256 i = 0; i < durationsCount; i++) {
            adapter.addDuration(possibleDurations[i]);
        }
        vm.stopPrank();

        bytes32[] memory ids = adapter.ids(obligation);
        assertEq(ids[0], adapter.adapterId());
        for (uint256 i = 0; i < obligation.collaterals.length; i++) {
            assertEq(ids[i * 2 + 1], keccak256(abi.encode("collateralToken", obligation.collaterals[i].token)));
            assertEq(
                ids[i * 2 + 2],
                keccak256(
                    abi.encode(
                        "collateral",
                        obligation.collaterals[i].token,
                        obligation.collaterals[i].oracle,
                        obligation.collaterals[i].lltv
                    )
                )
            );
        }

        uint256[] memory durationsArray = adapter.durations();
        uint256 durationIdCount = 0;
        for (uint256 i = 0; i < durationsArray.length; i++) {
            if ((obligation.maturity - block.timestamp) >= durationsArray[i]) {
                assertEq(
                    ids[1 + obligation.collaterals.length * 2 + durationIdCount],
                    keccak256(abi.encode("duration", durationsArray[i]))
                );
                durationIdCount++;
            }
        }

        assertEq(ids.length, 1 + obligation.collaterals.length * 2 + durationIdCount);
    }

    /* UTILITIES */

    function setCurrentGrowth(uint128 growth) internal {
        stdstore.target(address(adapter)).enable_packed_slots().sig("currentGrowth()").checked_write(growth);
    }

    function set_TotalAssets(uint256 _totalAssets) internal {
        stdstore.target(address(adapter)).sig("_totalAssets()").checked_write(_totalAssets);
    }

    function set_Durations(bytes32 _durations) internal {
        stdstore.target(address(adapter)).sig("_durations()").checked_write(_durations);
    }

    function removeCopies(uint256[] storage array) internal returns (uint256[] memory) {
        uint256[] memory sorted = vm.sort(array);
        uint256 numCopies = 0;
        for (uint256 i = 0; i + 1 < sorted.length; i++) {
            if (sorted[i] == sorted[i + 1]) numCopies++;
        }
        uint256[] memory res = new uint256[](sorted.length - numCopies);
        uint256 resIndex = 0;
        for (uint256 i = 0; i < sorted.length; i++) {
            if (i == 0 || sorted[i - 1] != sorted[i]) res[resIndex++] = sorted[i];
        }
        return res;
    }

    function _obligationId(Obligation memory obligation) internal pure returns (bytes32) {
        return keccak256(abi.encode(obligation));
    }

    function sign(Offer[1] memory offers) internal view returns (Signature memory) {
        return messageSig(root(offers), offers[0].maker);
    }

    function sign(Offer[1] memory offers, address signer) internal view returns (Signature memory) {
        return messageSig(root(offers), signer);
    }

    function proof(Offer[1] memory offers) internal pure returns (Proof memory) {
        return Proof({root: root(offers), path: new bytes32[](0)});
    }

    function sign(Offer[2] memory offers) internal view returns (Signature memory) {
        return messageSig(root(offers), offers[0].maker);
    }

    // assumes the offer is the first one!
    function proof(Offer[2] memory offers) internal pure returns (Proof memory) {
        Proof memory _proof = Proof({root: root(offers), path: new bytes32[](1)});
        _proof.path[0] = keccak256(abi.encode(offers[1]));
        return _proof;
    }

    function root(Offer memory offer) internal pure returns (bytes32) {
        return keccak256(abi.encode(offer));
    }

    function root(Offer[1] memory offers) internal pure returns (bytes32) {
        return keccak256(abi.encode(offers[0]));
    }

    function root(Offer[2] memory offers) internal pure returns (bytes32) {
        return keccak256(sort(keccak256(abi.encode(offers[0])), keccak256(abi.encode(offers[1]))));
    }

    function messageSig(bytes32 _root, address signer) internal view returns (Signature memory sig) {
        bytes32 messageHash = keccak256(bytes.concat("\x19\x45thereum Signed Message:\n32", _root));
        (sig.v, sig.r, sig.s) = vm.sign(privateKey[signer], messageHash);
    }

    /// @dev Returns the concatenation of x and y, sorted lexicographically.
    function sort(bytes32 x, bytes32 y) internal pure returns (bytes memory) {
        return x < y ? abi.encodePacked(x, y) : abi.encodePacked(y, x);
    }

    function assertEq(uint256[] memory left, uint256[1] memory right) internal pure {
        require(left.length == right.length, "lengths don't match (1)");
        for (uint256 i = 0; i < right.length; i++) {
            assertEq(left[i], right[i], "durations[i]");
        }
    }

    function assertEq(uint256[] memory left, uint256[2] memory right) internal pure {
        require(left.length == right.length, "lengths don't match (2)");
        for (uint256 i = 0; i < right.length; i++) {
            assertEq(left[i], right[i], "durations[i]");
        }
    }

    function assertEq(uint256[] memory left, uint256[3] memory right) internal pure {
        require(left.length == right.length, "lengths don't match (3)");
        for (uint256 i = 0; i < right.length; i++) {
            assertEq(left[i], right[i], "durations[i]");
        }
    }

    function assertEq(uint256[] memory left, uint256[8] memory right) internal pure {
        require(left.length == right.length, "lengths don't match (10)");
        for (uint256 i = 0; i < right.length; i++) {
            assertEq(left[i], right[i], "durations[i]");
        }
    }
}
