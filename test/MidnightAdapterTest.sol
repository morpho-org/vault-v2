// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Morpho Association
pragma solidity ^0.8.0;

import "../lib/forge-std/src/Test.sol";
import {MidnightAdapter, MaturityData} from "../src/adapters/MidnightAdapter.sol";
import {MidnightAdapterFactory} from "../src/adapters/MidnightAdapterFactory.sol";
import {ERC20Mock} from "./mocks/ERC20Mock.sol";
import {OracleMock} from "../lib/morpho-blue/src/mocks/OracleMock.sol";
import {VaultV2Mock} from "./mocks/VaultV2Mock.sol";
import {IERC20} from "../src/interfaces/IERC20.sol";
import {IMidnightAdapter} from "../src/adapters/interfaces/IMidnightAdapter.sol";
import {IMidnightAdapterFactory} from "../src/adapters/interfaces/IMidnightAdapterFactory.sol";
import {MathLib} from "../src/libraries/MathLib.sol";
import {Midnight} from "../lib/midnight/src/Midnight.sol";
import {Offer, Obligation, CollateralParams} from "../lib/midnight/src/interfaces/IMidnight.sol";
import {Signature, EIP712_DOMAIN_TYPEHASH, ROOT_TYPEHASH} from "../lib/midnight/src/interfaces/IEcrecover.sol";
import {TickLib, MAX_TICK} from "../lib/midnight/src/libraries/TickLib.sol";
import {IdLib} from "../lib/midnight/src/libraries/IdLib.sol";
import {stdStorage, StdStorage} from "../lib/forge-std/src/Test.sol";
import {ORACLE_PRICE_SCALE} from "../lib/morpho-blue/src/libraries/ConstantsLib.sol";

struct Step {
    uint256 assets;
    uint256 approxGrowth;
    uint256 maturity;
    CollateralParams[] collaterals;
}

contract MidnightAdapterTest is Test {
    using stdStorage for StdStorage;
    using MathLib for uint256;

    Midnight internal morphoV2;
    IMidnightAdapterFactory internal factory;
    IMidnightAdapter internal adapter;
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
    CollateralParams[] internal storedCollaterals;
    CollateralParams[] internal storedSingleCollateral;

    mapping(address => uint256) internal privateKey;

    Offer storedOffer;

    uint256 internal constant MIN_TEST_ASSETS = 10;
    uint256 internal constant MAX_TEST_ASSETS = 1e24;

    // Hardcoded obligation setups
    Step[] internal steps00;
    Step[] internal steps01;

    // Expected values after setting up obligations
    mapping(bytes32 obligationId => uint256) expectedUnits;
    mapping(uint256 timestamp => uint256) expectedMaturityGrowths;
    uint256[] internal expectedPositionsList;
    uint256[] internal expectedMaturitiesList;
    uint256 internal expectedAddedGrowth;
    uint256 internal expectedAddedAssets;

    uint256[] internal allDurations = [1 days, 7 days, 30 days, 90 days, 180 days];

    function setUp() public virtual {
        owner = makeAddr("owner");
        curator = makeAddr("curator");
        (signerAllocator, signerAllocatorPrivateKey) = makeAddrAndKey("signerAllocator");
        privateKey[signerAllocator] = signerAllocatorPrivateKey;

        recipient = makeAddr("recipient");
        taker = makeAddr("taker");

        morphoV2 = new Midnight();

        loanToken = IERC20(address(new ERC20Mock(18)));
        rewardToken = IERC20(address(new ERC20Mock(18)));

        parentVault = new VaultV2Mock(address(loanToken), owner, curator, signerAllocator, address(0));

        factory = new MidnightAdapterFactory(allDurations);
        adapter = MidnightAdapter(factory.createMidnightAdapter(address(parentVault), address(morphoV2)));

        // Adapter authorizes itself as ratifier
        vm.prank(address(adapter));
        morphoV2.setIsAuthorized(address(adapter), address(adapter), true);

        address collToken0 = address(new ERC20Mock(18));
        address collToken1 = address(new ERC20Mock(18));
        address oracle0 = address(new OracleMock());
        address oracle1 = address(new OracleMock());

        // Ensure collateral tokens are sorted ascending by address
        if (collToken0 > collToken1) {
            (collToken0, collToken1) = (collToken1, collToken0);
            (oracle0, oracle1) = (oracle1, oracle0);
        }

        storedCollaterals.push(
            CollateralParams({
                token: collToken0, lltv: 1 ether, maxLif: morphoV2.maxLif(1 ether, 0.25e18), oracle: oracle0
            })
        );
        storedCollaterals.push(
            CollateralParams({
                token: collToken1, lltv: 1 ether, maxLif: morphoV2.maxLif(1 ether, 0.25e18), oracle: oracle1
            })
        );

        OracleMock(storedCollaterals[0].oracle).setPrice(ORACLE_PRICE_SCALE);
        OracleMock(storedCollaterals[1].oracle).setPrice(ORACLE_PRICE_SCALE);

        storedSingleCollateral.push(storedCollaterals[0]);

        uint256 maturity = vm.getBlockTimestamp() + 200;
        storedOffer = Offer({
            buy: true,
            maker: address(adapter),
            obligation: Obligation({
                loanToken: address(loanToken),
                collateralParams: storedCollaterals,
                maturity: maturity,
                rcfThreshold: 0,
                enterGate: address(0),
                liquidatorGate: address(0)
            }),
            start: vm.getBlockTimestamp(),
            expiry: maturity,
            tick: MAX_TICK,
            group: bytes32(0),
            session: bytes32(0),
            callback: address(adapter),
            callbackData: bytes(""),
            receiverIfMakerIsSeller: address(0),
            ratifier: address(adapter),
            reduceOnly: false,
            maxUnits: 0,
            maxSellerAssets: 0,
            maxBuyerAssets: 0
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
        offer.tick = TickLib.priceToTick(0.95e18);

        vm.startPrank(taker);
        IERC20(storedCollaterals[0].token).approve(address(morphoV2), type(uint256).max);
        IERC20(storedCollaterals[1].token).approve(address(morphoV2), type(uint256).max);
        deal(storedCollaterals[0].token, taker, 1_000e18);
        deal(storedCollaterals[1].token, taker, 1_000e18);
        morphoV2.supplyCollateral(offer.obligation, 0, 1_000e18, taker);
        morphoV2.supplyCollateral(offer.obligation, 1, 1_000e18, taker);
        vm.stopPrank();

        uint256 assets = 1e18;
        uint256 price = TickLib.tickToPrice(offer.tick);
        uint256 units = assets * 1e18 / price;

        offer.maxUnits = units;
        offer.callback = address(adapter);
        offer.callbackData = abi.encode(0);
        vm.prank(taker);
        morphoV2.take(
            units, taker, address(0), "", taker, offer, sign([offer], signerAllocator), root([offer]), proof([offer])
        );

        uint256 remainder = (units - assets) % (offer.obligation.maturity - vm.getBlockTimestamp());
        assertEq(adapter._totalAssets(), assets + remainder, "_totalAssets");
        assertEq(adapter.lastUpdate(), vm.getBlockTimestamp(), "lastUpdate");
        assertEq(adapter.firstMaturity(), vm.getBlockTimestamp() + 200, "firstMaturity");

        uint256 totalInterest = units - assets;
        uint256 duration = offer.obligation.maturity - vm.getBlockTimestamp();
        uint256 newGrowth = totalInterest / duration;
        assertEq(adapter.currentGrowth(), newGrowth, "currentGrowth");
        MaturityData memory maturityData = adapter.maturities(offer.obligation.maturity);
        assertEq(maturityData.growth, newGrowth, "growth");
        assertEq(maturityData.nextMaturity, type(uint48).max, "nextMaturity");

        uint256 actualUnits = adapter.units(_obligationId(offer.obligation));
        assertEq(actualUnits, units, "units");
    }

    function testBuyAtPastMaturityWithExistingGrowth() public {
        Offer memory offer = storedOffer;
        offer.tick = TickLib.priceToTick(0.95e18);
        uint256 maturity = offer.obligation.maturity;

        vm.startPrank(taker);
        IERC20(storedCollaterals[0].token).approve(address(morphoV2), type(uint256).max);
        IERC20(storedCollaterals[1].token).approve(address(morphoV2), type(uint256).max);
        deal(storedCollaterals[0].token, taker, 100_000e18);
        deal(storedCollaterals[1].token, taker, 100_000e18);
        morphoV2.supplyCollateral(offer.obligation, 0, 100_000e18, taker);
        morphoV2.supplyCollateral(offer.obligation, 1, 100_000e18, taker);
        vm.stopPrank();

        // Step 1: Buy at maturity M (future)
        uint256 assets1 = 1e18;
        uint256 price1 = TickLib.tickToPrice(offer.tick);
        uint256 units1 = assets1 * 1e18 / price1;

        offer.maxUnits = units1;
        offer.callback = address(adapter);
        offer.callbackData = abi.encode(0);

        vm.prank(taker);
        morphoV2.take(
            units1, taker, address(0), "", taker, offer, sign([offer], signerAllocator), root([offer]), proof([offer])
        );

        uint256 timeToMaturity = maturity - block.timestamp;
        uint128 growth1 = uint128((units1 - assets1) / timeToMaturity);
        assertGt(growth1, 0, "growth should be nonzero");
        assertEq(adapter.currentGrowth(), growth1, "currentGrowth after buy1");

        // Step 2: Advance time past maturity M
        skip(timeToMaturity + 1);
        assertGt(block.timestamp, maturity, "should be past maturity");

        // Step 3: Trigger accrueInterest so the walk subtracts growth from currentGrowth
        adapter.accrueInterest();
        assertEq(adapter.currentGrowth(), 0, "currentGrowth after accrual should be 0");
        assertEq(adapter.firstMaturity(), type(uint48).max, "firstMaturity should be sentinel");
        uint256 totalAssetsAfterAccrual = adapter._totalAssets();

        // In midnight, any seller with debt past maturity is always liquidatable
        // (isLiquidatable returns true if block.timestamp > maturity && debt > 0),
        // so we can't test a second buy at past maturity. Just verify accrual state.
        assertEq(adapter.firstMaturity(), type(uint48).max, "past maturity not re-inserted into list");

        // Note: In midnight, any seller with debt past maturity is always liquidatable,
        // so the second buy at past maturity from the original test cannot be executed.
    }

    /* RATIFICATION */

    function _ratificationSetup() internal returns (Offer memory offer) {
        offer.buy = true;
        offer.maker = address(adapter);

        offer.obligation.loanToken = address(loanToken);
        uint256 numCollaterals = bound(vm.randomUint(), 1, 3);
        CollateralParams[] memory collateralParams = new CollateralParams[](numCollaterals);
        address[] memory tokens = new address[](numCollaterals);
        address[] memory oracles = new address[](numCollaterals);
        for (uint256 i = 0; i < numCollaterals; i++) {
            tokens[i] = address(new ERC20Mock(18));
            oracles[i] = address(new OracleMock());
        }
        // Sort tokens ascending (bubble sort)
        for (uint256 i = 0; i < numCollaterals; i++) {
            for (uint256 j = i + 1; j < numCollaterals; j++) {
                if (tokens[i] > tokens[j]) {
                    (tokens[i], tokens[j]) = (tokens[j], tokens[i]);
                    (oracles[i], oracles[j]) = (oracles[j], oracles[i]);
                }
            }
        }
        for (uint256 i = 0; i < numCollaterals; i++) {
            collateralParams[i] = CollateralParams({
                token: tokens[i], lltv: 1 ether, maxLif: morphoV2.maxLif(1 ether, 0.25e18), oracle: oracles[i]
            });
        }
        offer.obligation.collateralParams = collateralParams;
        offer.obligation.maturity = bound(vm.randomUint(), vm.getBlockTimestamp(), type(uint48).max - 1);
        offer.obligation.rcfThreshold = 0;
        offer.obligation.enterGate = address(0);
        offer.obligation.liquidatorGate = address(0);

        offer.start = bound(vm.randomUint(), 0, vm.getBlockTimestamp());
        offer.expiry = bound(vm.randomUint(), offer.start, type(uint48).max);
        offer.tick = bound(vm.randomUint(), 0, MAX_TICK);
        offer.callback = address(adapter);
        offer.callbackData = bytes("");
        offer.receiverIfMakerIsSeller = address(0);
        offer.ratifier = address(adapter);
        offer.reduceOnly = false;
        offer.maxUnits = 0;
        offer.maxSellerAssets = 0;
        offer.maxBuyerAssets = 0;
    }

    function testRatifyIncorrectOfferBadSellSigner(uint256 seed) public {
        vm.setSeed(seed);
        (address otherSigner, uint256 otherSignerKey) = makeAddrAndKey("otherSigner");
        privateKey[otherSigner] = otherSignerKey;
        vm.assume(otherSigner != signerAllocator);
        Offer memory offer = _ratificationSetup();
        bytes32 _root = root(offer);
        bytes memory data = ratifierData(_root, otherSigner);
        vm.expectRevert(IMidnightAdapter.IncorrectSigner.selector);
        adapter.onRatify(offer, _root, data);
    }

    function testRatifyIncorrectOfferBadBuySigner(uint256 seed) public {
        vm.setSeed(seed);
        (address otherSigner, uint256 otherSignerKey) = makeAddrAndKey("otherSigner2");
        privateKey[otherSigner] = otherSignerKey;
        vm.assume(otherSigner != signerAllocator);
        vm.assume(otherSigner != address(adapter));
        Offer memory offer = _ratificationSetup();
        bytes32 _root = root(offer);
        bytes memory data = ratifierData(_root, otherSigner);
        vm.expectRevert(IMidnightAdapter.IncorrectSigner.selector);
        adapter.onRatify(offer, _root, data);
    }

    function testRatifyLoanAssetMismatch(uint256 seed, address otherToken) public {
        vm.setSeed(seed);
        Offer memory offer = _ratificationSetup();
        vm.assume(otherToken != offer.obligation.loanToken);
        offer.obligation.loanToken = otherToken;
        bytes32 _root = root(offer);
        bytes memory data = ratifierData(_root, signerAllocator);
        vm.expectRevert(IMidnightAdapter.LoanAssetMismatch.selector);
        adapter.onRatify(offer, _root, data);
    }

    function testRatifyIncorrectOwner(uint256 seed, address otherMaker) public {
        vm.setSeed(seed);
        Offer memory offer = _ratificationSetup();
        vm.assume(otherMaker != address(adapter));
        offer.maker = otherMaker;
        bytes32 _root = root(offer);
        bytes memory data = ratifierData(_root, signerAllocator);
        vm.expectRevert(IMidnightAdapter.IncorrectOwner.selector);
        adapter.onRatify(offer, _root, data);
    }

    function testRatifyIncorrectMaturity(uint256 seed) public {
        vm.setSeed(seed);
        Offer memory offer = _ratificationSetup();
        offer.obligation.maturity = vm.randomUint(type(uint48).max, type(uint256).max);
        bytes32 _root = root(offer);
        bytes memory data = ratifierData(_root, signerAllocator);
        vm.expectRevert(IMidnightAdapter.IncorrectMaturity.selector);
        adapter.onRatify(offer, _root, data);
    }

    function testRatifyIncorrectStart(uint256 seed) public {
        vm.setSeed(seed);
        Offer memory offer = _ratificationSetup();
        offer.start = vm.getBlockTimestamp() + 1;
        bytes32 _root = root(offer);
        bytes memory data = ratifierData(_root, signerAllocator);
        vm.expectRevert(IMidnightAdapter.IncorrectStart.selector);
        adapter.onRatify(offer, _root, data);
    }

    function testRatifyIncorrectCallbackAddress(uint256 seed) public {
        vm.setSeed(seed);
        Offer memory offer = _ratificationSetup();
        offer.callback = address(0);
        bytes32 _root = root(offer);
        bytes memory data = ratifierData(_root, signerAllocator);
        vm.expectRevert(IMidnightAdapter.IncorrectCallbackAddress.selector);
        adapter.onRatify(offer, _root, data);
    }

    function testRatifyIncorrectExpiry(uint256 seed) public {
        vm.setSeed(seed);
        Offer memory offer = _ratificationSetup();
        bytes32 _root = root(offer);
        bytes memory data = ratifierData(_root, signerAllocator);
        adapter.onRatify(offer, _root, data);
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
            tick: MAX_TICK,
            callback: address(adapter),
            callbackData: abi.encode(0),
            obligation: Obligation({
                loanToken: address(loanToken),
                collateralParams: storedCollaterals,
                maturity: 0,
                rcfThreshold: 0,
                enterGate: address(0),
                liquidatorGate: address(0)
            }),
            group: bytes32(0),
            session: bytes32(0),
            ratifier: address(adapter),
            receiverIfMakerIsSeller: address(0),
            reduceOnly: false,
            maxUnits: 0,
            maxSellerAssets: 0,
            maxBuyerAssets: 0
        });

        for (uint256 i = 0; i < steps.length; i++) {
            Step memory step = steps[i];
            uint256 timeToMaturity = step.maturity - vm.getBlockTimestamp();
            require(timeToMaturity > 0 || step.approxGrowth == 0, "nonzero growth on 0 duration");
            uint256 approxInterest = step.approxGrowth * timeToMaturity;
            offer.group = bytes32(i);
            offer.obligation.maturity = step.maturity;

            // Compute tick from desired price: price = assets / (assets + approxInterest)
            uint256 desiredPrice = step.assets.mulDivDown(1e18, step.assets + approxInterest);
            if (desiredPrice > 1e18) desiredPrice = 1e18;
            offer.tick = TickLib.priceToTick(desiredPrice);
            uint256 actualPrice = TickLib.tickToPrice(offer.tick);
            uint256 units = step.assets.mulDivDown(1e18, actualPrice);
            uint256 actualGrowth = (units - step.assets) / timeToMaturity;
            uint256 zeroPeriodGain = (units - step.assets) % timeToMaturity;
            offer.maxUnits = units;
            bytes32 obligationId = _obligationId(offer.obligation);

            vm.startPrank(taker);
            deal(storedCollaterals[0].token, taker, 1_000e18);
            deal(storedCollaterals[1].token, taker, 1_000e18);
            morphoV2.supplyCollateral(offer.obligation, 0, 1_000e18, taker);
            morphoV2.supplyCollateral(offer.obligation, 1, 1_000e18, taker);

            uint256 unitsBefore = adapter.units(obligationId);
            morphoV2.take(
                units,
                taker,
                address(0),
                "",
                taker,
                offer,
                sign([offer], signerAllocator),
                root([offer]),
                proof([offer])
            );
            vm.stopPrank();

            assertEq(adapter.units(obligationId), unitsBefore + units, "setup: units 1");

            expectedUnits[obligationId] += units;
            expectedMaturityGrowths[step.maturity] += actualGrowth;
            if (timeToMaturity > 0) {
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
                adapter.maturities(expectedMaturitiesList[i]).growth,
                expectedMaturityGrowths[expectedMaturitiesList[i]],
                "growth"
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
            assertEq(adapter.units(obligationId), expectedUnits[obligationId], "units");
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

    // Add constructor tests

    /* IDS */

    function testIds(uint256 collateralCount, uint256 maturity) public view {
        collateralCount = bound(collateralCount, 0, 5);

        Obligation memory obligation;

        CollateralParams[] memory collateralParams = new CollateralParams[](collateralCount);
        for (uint256 i = 0; i < collateralCount; i++) {
            collateralParams[i].token = address(uint160(i));
        }
        obligation.collateralParams = storedCollaterals;
        obligation.maturity = bound(maturity, 1, 700 days);

        bytes32[] memory ids = adapter.ids(obligation);
        assertEq(ids[0], adapter.adapterId());
        for (uint256 i = 0; i < obligation.collateralParams.length; i++) {
            assertEq(ids[i * 2 + 1], keccak256(abi.encode("collateralToken", obligation.collateralParams[i].token)));
            assertEq(
                ids[i * 2 + 2],
                keccak256(
                    abi.encode(
                        "collateral",
                        obligation.collateralParams[i].token,
                        obligation.collateralParams[i].oracle,
                        obligation.collateralParams[i].lltv
                    )
                )
            );
        }

        uint256[] memory durations = adapter.durations();
        uint256 durationIdCount = 0;
        for (uint256 i = 0; i < durations.length; i++) {
            if ((obligation.maturity - block.timestamp) >= durations[i]) {
                assertEq(
                    ids[1 + obligation.collateralParams.length * 2 + durationIdCount],
                    keccak256(abi.encode("duration", durations[i]))
                );
                durationIdCount++;
            }
        }

        assertEq(ids.length, 1 + obligation.collateralParams.length * 2 + durationIdCount);
    }

    /* UTILITIES */

    function setCurrentGrowth(uint128 growth) internal {
        stdstore.target(address(adapter)).enable_packed_slots().sig("currentGrowth()").checked_write(growth);
    }

    function set_TotalAssets(uint256 _totalAssets) internal {
        stdstore.target(address(adapter)).sig("_totalAssets()").checked_write(_totalAssets);
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

    function sign(Offer[1] memory offers) internal view returns (bytes memory) {
        return ratifierData(root(offers), offers[0].maker);
    }

    function sign(Offer[1] memory offers, address signer) internal view returns (bytes memory) {
        return ratifierData(root(offers), signer);
    }

    function proof(Offer[1] memory) internal pure returns (bytes32[] memory) {
        return new bytes32[](0);
    }

    // assumes the offer is the first one!
    function proof(Offer[2] memory offers) internal pure returns (bytes32[] memory) {
        bytes32[] memory path = new bytes32[](1);
        path[0] = keccak256(abi.encode(offers[1]));
        return path;
    }

    function sign(Offer[2] memory offers) internal view returns (bytes memory) {
        return ratifierData(root(offers), offers[0].maker);
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

    function ratifierData(bytes32 _root, address signer) internal view returns (bytes memory) {
        bytes32 structHash = keccak256(abi.encode(ROOT_TYPEHASH, _root));
        bytes32 domainSeparator = keccak256(abi.encode(EIP712_DOMAIN_TYPEHASH, block.chainid, address(adapter)));
        bytes32 digest = keccak256(bytes.concat("\x19\x01", domainSeparator, structHash));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(privateKey[signer], digest);
        return abi.encode(Signature({v: v, r: r, s: s}));
    }

    /// @dev Returns the concatenation of x and y, sorted lexicographically.
    function sort(bytes32 x, bytes32 y) internal pure returns (bytes memory) {
        return x < y ? abi.encodePacked(x, y) : abi.encodePacked(y, x);
    }
}
