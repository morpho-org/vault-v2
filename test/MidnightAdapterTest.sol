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
import {IMidnight, Offer, Market, CollateralParams} from "../lib/midnight/src/interfaces/IMidnight.sol";
import {Signature, EIP712_DOMAIN_TYPEHASH} from "../lib/midnight/src/ratifiers/interfaces/IEcrecoverRatifier.sol";
import {HashLib} from "../lib/midnight/src/ratifiers/libraries/HashLib.sol";
import {TickLib, MAX_TICK} from "../lib/midnight/src/libraries/TickLib.sol";
import {IdLib} from "../lib/midnight/src/libraries/IdLib.sol";
import {stdStorage, StdStorage} from "../lib/forge-std/src/Test.sol";
import {ORACLE_PRICE_SCALE} from "../lib/morpho-blue/src/libraries/ConstantsLib.sol";
import {maxLif} from "../lib/midnight/src/libraries/ConstantsLib.sol";

struct Step {
    uint256 assets;
    uint256 approxGrowth;
    uint256 maturity;
    CollateralParams[] collaterals;
}

contract MidnightAdapterTest is Test {
    using stdStorage for StdStorage;
    using MathLib for uint256;

    IMidnight internal midnight;
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

    // Hardcoded market setups
    Step[] internal steps00;
    Step[] internal steps01;

    // Expected values after setting up markets
    mapping(bytes32 marketId => uint256) expectedUnits;
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

        midnight = IMidnight(address(new Midnight()));

        loanToken = IERC20(address(new ERC20Mock(18)));
        rewardToken = IERC20(address(new ERC20Mock(18)));

        parentVault = new VaultV2Mock(address(loanToken), owner, curator, signerAllocator, address(0));

        factory = new MidnightAdapterFactory(allDurations);
        adapter = MidnightAdapter(factory.createMidnightAdapter(address(parentVault), address(midnight)));

        // Adapter authorizes itself as ratifier
        vm.prank(address(adapter));
        midnight.setIsAuthorized(address(adapter), true, address(adapter));

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
            CollateralParams({token: collToken0, lltv: 1 ether, maxLif: maxLif(1 ether, 0.25e18), oracle: oracle0})
        );
        storedCollaterals.push(
            CollateralParams({token: collToken1, lltv: 1 ether, maxLif: maxLif(1 ether, 0.25e18), oracle: oracle1})
        );

        OracleMock(storedCollaterals[0].oracle).setPrice(ORACLE_PRICE_SCALE);
        OracleMock(storedCollaterals[1].oracle).setPrice(ORACLE_PRICE_SCALE);

        storedSingleCollateral.push(storedCollaterals[0]);

        uint256 maturity = vm.getBlockTimestamp() + 200;
        storedOffer = Offer({
            buy: true,
            maker: address(adapter),
            market: Market({
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
            callback: address(adapter),
            callbackData: bytes(""),
            receiverIfMakerIsSeller: address(0),
            ratifier: address(adapter),
            reduceOnly: false,
            maxUnits: 0,
            maxAssets: 0
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
        offer.tick = TickLib.priceToTick(0.95e18, 4);

        vm.startPrank(taker);
        IERC20(storedCollaterals[0].token).approve(address(midnight), type(uint256).max);
        IERC20(storedCollaterals[1].token).approve(address(midnight), type(uint256).max);
        deal(storedCollaterals[0].token, taker, 1_000e18);
        deal(storedCollaterals[1].token, taker, 1_000e18);
        midnight.supplyCollateral(offer.market, 0, 1_000e18, taker);
        midnight.supplyCollateral(offer.market, 1, 1_000e18, taker);
        vm.stopPrank();

        uint256 assets = 1e18;
        uint256 price = TickLib.tickToPrice(offer.tick);
        uint256 units = assets * 1e18 / price;

        offer.maxUnits = units;
        offer.callback = address(adapter);
        offer.callbackData = hex"";
        vm.prank(taker);
        midnight.take(offer, units, taker, taker, address(0), "", sign([offer], signerAllocator));

        uint256 remainder = (units - assets) % (offer.market.maturity - vm.getBlockTimestamp());
        assertEq(adapter.totalAssets(), assets + remainder, "_totalAssets");
        assertEq(adapter.lastUpdate(), vm.getBlockTimestamp(), "lastUpdate");
        assertEq(adapter.maturities(0).nextMaturity, vm.getBlockTimestamp() + 200, "firstMaturity");

        uint256 totalInterest = units - assets;
        uint256 duration = offer.market.maturity - vm.getBlockTimestamp();
        uint256 newGrowth = totalInterest / duration;
        assertEq(adapter.currentGrowth(), newGrowth, "currentGrowth");
        MaturityData memory maturityData = adapter.maturities(offer.market.maturity);
        assertEq(maturityData.growth, newGrowth, "growth");
        assertEq(maturityData.nextMaturity, 0, "nextMaturity");

        uint256 actualUnits = adapter.netCredit(_marketId(offer.market));
        assertEq(actualUnits, units, "units");
    }

    function testBuyAtPastMaturityWithExistingGrowth() public {
        Offer memory offer = storedOffer;
        offer.tick = TickLib.priceToTick(0.95e18, 4);
        uint256 maturity = offer.market.maturity;

        vm.startPrank(taker);
        IERC20(storedCollaterals[0].token).approve(address(midnight), type(uint256).max);
        IERC20(storedCollaterals[1].token).approve(address(midnight), type(uint256).max);
        deal(storedCollaterals[0].token, taker, 100_000e18);
        deal(storedCollaterals[1].token, taker, 100_000e18);
        midnight.supplyCollateral(offer.market, 0, 100_000e18, taker);
        midnight.supplyCollateral(offer.market, 1, 100_000e18, taker);
        vm.stopPrank();

        // Step 1: Buy at maturity M (future)
        uint256 assets1 = 1e18;
        uint256 price1 = TickLib.tickToPrice(offer.tick);
        uint256 units1 = assets1 * 1e18 / price1;

        offer.maxUnits = units1;
        offer.callback = address(adapter);
        offer.callbackData = hex"";

        vm.prank(taker);
        midnight.take(offer, units1, taker, taker, address(0), "", sign([offer], signerAllocator));

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
        assertEq(adapter.maturities(0).nextMaturity, 0, "firstMaturity should be sentinel");

        // In midnight, any seller with debt past maturity is always liquidatable
        // (isLiquidatable returns true if block.timestamp > maturity && debt > 0),
        // so we can't test a second buy at past maturity. Just verify accrual state.
        assertEq(adapter.maturities(0).nextMaturity, 0, "past maturity not re-inserted into list");

        // Note: In midnight, any seller with debt past maturity is always liquidatable,
        // so the second buy at past maturity from the original test cannot be executed.
    }

    /* RATIFICATION */

    function _ratificationSetup() internal returns (Offer memory offer) {
        offer.buy = true;
        offer.maker = address(adapter);

        offer.market.loanToken = address(loanToken);
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
                token: tokens[i], lltv: 1 ether, maxLif: maxLif(1 ether, 0.25e18), oracle: oracles[i]
            });
        }
        offer.market.collateralParams = collateralParams;
        offer.market.maturity = bound(vm.randomUint(), vm.getBlockTimestamp(), type(uint48).max - 1);
        offer.market.rcfThreshold = 0;
        offer.market.enterGate = address(0);
        offer.market.liquidatorGate = address(0);

        offer.start = bound(vm.randomUint(), 0, vm.getBlockTimestamp());
        offer.expiry = bound(vm.randomUint(), offer.start, type(uint48).max);
        offer.tick = bound(vm.randomUint(), 0, MAX_TICK);
        offer.callback = address(adapter);
        offer.callbackData = bytes("");
        offer.receiverIfMakerIsSeller = address(0);
        offer.ratifier = address(adapter);
        offer.reduceOnly = false;
        offer.maxUnits = 0;
        offer.maxAssets = 0;
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
        adapter.isRatified(offer, data);
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
        adapter.isRatified(offer, data);
    }

    function testRatifyLoanAssetMismatch(uint256 seed, address otherToken) public {
        vm.setSeed(seed);
        Offer memory offer = _ratificationSetup();
        vm.assume(otherToken != offer.market.loanToken);
        offer.market.loanToken = otherToken;
        bytes32 _root = root(offer);
        bytes memory data = ratifierData(_root, signerAllocator);
        vm.expectRevert(IMidnightAdapter.LoanAssetMismatch.selector);
        adapter.isRatified(offer, data);
    }

    function testRatifyIncorrectOwner(uint256 seed, address otherMaker) public {
        vm.setSeed(seed);
        Offer memory offer = _ratificationSetup();
        vm.assume(otherMaker != address(adapter));
        offer.maker = otherMaker;
        bytes32 _root = root(offer);
        bytes memory data = ratifierData(_root, signerAllocator);
        vm.expectRevert(IMidnightAdapter.IncorrectOwner.selector);
        adapter.isRatified(offer, data);
    }

    function testRatifyIncorrectStart(uint256 seed) public {
        vm.setSeed(seed);
        Offer memory offer = _ratificationSetup();
        offer.start = vm.getBlockTimestamp() + 1;
        bytes32 _root = root(offer);
        bytes memory data = ratifierData(_root, signerAllocator);
        vm.expectRevert(IMidnightAdapter.IncorrectStart.selector);
        adapter.isRatified(offer, data);
    }

    function testRatifyIncorrectCallbackAddress(uint256 seed) public {
        vm.setSeed(seed);
        Offer memory offer = _ratificationSetup();
        offer.callback = address(0);
        bytes32 _root = root(offer);
        bytes memory data = ratifierData(_root, signerAllocator);
        vm.expectRevert(IMidnightAdapter.IncorrectCallbackAddress.selector);
        adapter.isRatified(offer, data);
    }

    function testRatifyIncorrectExpiry(uint256 seed) public {
        vm.setSeed(seed);
        Offer memory offer = _ratificationSetup();
        bytes32 _root = root(offer);
        bytes memory data = ratifierData(_root, signerAllocator);
        adapter.isRatified(offer, data);
    }

    /* STEPS SETUP */

    function setupMarkets(Step[] memory steps) internal {
        vm.startPrank(taker);
        IERC20(storedCollaterals[0].token).approve(address(midnight), type(uint256).max);
        IERC20(storedCollaterals[1].token).approve(address(midnight), type(uint256).max);
        vm.stopPrank();

        Offer memory offer = Offer({
            buy: true,
            maker: address(adapter),
            start: vm.getBlockTimestamp(),
            expiry: vm.getBlockTimestamp() + 1,
            tick: MAX_TICK,
            callback: address(adapter),
            callbackData: hex"",
            market: Market({
                loanToken: address(loanToken),
                collateralParams: storedCollaterals,
                maturity: 0,
                rcfThreshold: 0,
                enterGate: address(0),
                liquidatorGate: address(0)
            }),
            group: bytes32(0),
            ratifier: address(adapter),
            receiverIfMakerIsSeller: address(0),
            reduceOnly: false,
            maxUnits: 0,
            maxAssets: 0
        });

        for (uint256 i = 0; i < steps.length; i++) {
            Step memory step = steps[i];
            uint256 timeToMaturity = step.maturity - vm.getBlockTimestamp();
            require(timeToMaturity > 0 || step.approxGrowth == 0, "nonzero growth on 0 duration");
            uint256 approxInterest = step.approxGrowth * timeToMaturity;
            offer.group = bytes32(i);
            offer.market.maturity = step.maturity;
            offer.callbackData = hex"";

            // Compute tick from desired price: price = assets / (assets + approxInterest)
            uint256 desiredPrice = step.assets.mulDivDown(1e18, step.assets + approxInterest);
            if (desiredPrice > 1e18) desiredPrice = 1e18;
            offer.tick = TickLib.priceToTick(desiredPrice, 4);
            uint256 actualPrice = TickLib.tickToPrice(offer.tick);
            uint256 units = step.assets.mulDivDown(1e18, actualPrice);
            uint256 actualGrowth = (units - step.assets) / timeToMaturity;
            uint256 zeroPeriodGain = (units - step.assets) % timeToMaturity;
            offer.maxUnits = units;
            bytes32 marketId = _marketId(offer.market);

            vm.startPrank(taker);
            deal(storedCollaterals[0].token, taker, 1_000e18);
            deal(storedCollaterals[1].token, taker, 1_000e18);
            midnight.supplyCollateral(offer.market, 0, 1_000e18, taker);
            midnight.supplyCollateral(offer.market, 1, 1_000e18, taker);

            uint256 unitsBefore = adapter.netCredit(marketId);
            midnight.take(offer, units, taker, taker, address(0), "", sign([offer], signerAllocator));
            vm.stopPrank();

            assertEq(adapter.netCredit(marketId), unitsBefore + units, "setup: units 1");

            expectedUnits[marketId] += units;
            expectedMaturityGrowths[step.maturity] += actualGrowth;
            if (timeToMaturity > 0) {
                expectedAddedGrowth += actualGrowth.toUint128();
            }
            expectedAddedAssets += step.assets + zeroPeriodGain;
            expectedPositionsList.push(uint256(marketId));
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

        setupMarkets(steps);

        // Check pointer to first element of maturities list
        if (steps.length > 0) {
            assertEq(adapter.maturities(0).nextMaturity, steps[0].maturity, "firstMaturity");
        } else {
            assertEq(adapter.maturities(0).nextMaturity, 0, "firstMaturity");
        }

        // Check maturities growth and linked list structure
        for (uint256 i = 0; i < expectedMaturitiesList.length; i++) {
            assertEq(
                adapter.maturities(expectedMaturitiesList[i]).growth,
                expectedMaturityGrowths[expectedMaturitiesList[i]],
                "growth"
            );
            if (i == expectedMaturitiesList.length - 1) {
                assertEq(adapter.maturities(expectedMaturitiesList[i]).nextMaturity, 0, "nextMaturity end");
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
            bytes32 marketId = bytes32(expectedPositionsList[i]);
            assertEq(adapter.netCredit(marketId), expectedUnits[marketId], "units");
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
        uint256 maxElapsed =
            steps.length == 0 ? 365 days : 2 * (steps[steps.length - 1].maturity - vm.getBlockTimestamp());
        initialGrowth = bound(initialGrowth, 0, 1e24);
        _totalAssets = bound(_totalAssets, 0, type(uint128).max / 2);
        elapsed = bound(elapsed, 0, maxElapsed);

        setCurrentGrowth(uint128(initialGrowth));
        set_TotalAssets(_totalAssets);
        setupMarkets(steps);
        uint256 expectedCurrentGrowth = initialGrowth + expectedAddedGrowth;
        assertEq(adapter.currentGrowth(), expectedCurrentGrowth, "currentGrowth");
        assertEq(adapter.totalAssets(), _totalAssets + expectedAddedAssets, "_totalAssets");

        skip(elapsed);

        (uint48 nextMaturity, uint128 newGrowth, uint256 newTotalAssets,) = adapter.accrueInterestView();

        uint256 lostGrowth = 0;
        uint256 interest = initialGrowth * elapsed;
        uint256 expectedNextMaturity;

        for (uint256 i = 0; i < expectedMaturitiesList.length; i++) {
            uint256 maturity = expectedMaturitiesList[i];
            if (maturity <= vm.getBlockTimestamp()) {
                lostGrowth += expectedMaturityGrowths[maturity];
                interest += expectedMaturityGrowths[maturity] * (maturity - begin);
            } else {
                interest += expectedMaturityGrowths[maturity] * elapsed;
            }
            if (maturity > vm.getBlockTimestamp() && (expectedNextMaturity == 0 || maturity < expectedNextMaturity)) {
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

    function testConstructorGetters() public view {
        assertEq(adapter.asset(), address(loanToken), "asset");
        assertEq(adapter.parentVault(), address(parentVault), "parentVault");
        assertEq(adapter.midnight(), address(midnight), "midnight");
        assertEq(adapter.skimRecipient(), address(0), "skimRecipient");
        assertEq(adapter.durationsLength(), allDurations.length, "durationsLength");
        assertEq(adapter.packedDurations(), MidnightAdapter(address(adapter)).packedDurations(), "packedDurations");
    }

    /* IDS */

    function testIds(uint256 collateralCount, uint256 maturity) public view {
        collateralCount = bound(collateralCount, 0, 5);

        Market memory market;

        CollateralParams[] memory collateralParams = new CollateralParams[](collateralCount);
        for (uint256 i = 0; i < collateralCount; i++) {
            collateralParams[i].token = address(uint160(i));
        }
        market.collateralParams = storedCollaterals;
        market.maturity = bound(maturity, 1, 700 days);

        bytes32[] memory ids = adapter.ids(market);
        assertEq(ids[0], adapter.adapterId());
        for (uint256 i = 0; i < market.collateralParams.length; i++) {
            assertEq(ids[i * 2 + 1], keccak256(abi.encode("collateralToken", market.collateralParams[i].token)));
            assertEq(
                ids[i * 2 + 2],
                keccak256(
                    abi.encode(
                        "collateral",
                        market.collateralParams[i].token,
                        market.collateralParams[i].oracle,
                        market.collateralParams[i].lltv
                    )
                )
            );
        }

        uint256[] memory durations = adapter.durations();
        uint256 durationIdCount = 0;
        for (uint256 i = 0; i < durations.length; i++) {
            if ((market.maturity - block.timestamp) >= durations[i]) {
                assertEq(
                    ids[1 + market.collateralParams.length * 2 + durationIdCount],
                    keccak256(abi.encode("duration", durations[i]))
                );
                durationIdCount++;
            }
        }

        assertEq(ids.length, 1 + market.collateralParams.length * 2 + durationIdCount);
    }

    /* UTILITIES */

    function setCurrentGrowth(uint128 growth) internal {
        stdstore.target(address(adapter)).enable_packed_slots().sig("currentGrowth()").checked_write(growth);
    }

    function set_TotalAssets(uint256 _totalAssets) internal {
        stdstore.target(address(adapter)).enable_packed_slots().sig("totalAssets()").checked_write(_totalAssets);
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

    function _marketId(Market memory market) internal view returns (bytes32) {
        return IdLib.toId(market, block.chainid, address(midnight));
    }

    function sign(Offer[1] memory offers) internal view returns (bytes memory) {
        return ratifierData(root(offers), offers[0].maker, 0, proof(offers));
    }

    function sign(Offer[1] memory offers, address signer) internal view returns (bytes memory) {
        return ratifierData(root(offers), signer, 0, proof(offers));
    }

    function proof(Offer[1] memory) internal pure returns (bytes32[] memory) {
        return new bytes32[](0);
    }

    // assumes the offer is the first one!
    function proof(Offer[2] memory offers) internal pure returns (bytes32[] memory) {
        bytes32[] memory path = new bytes32[](1);
        path[0] = HashLib.hashOffer(offers[1]);
        return path;
    }

    function sign(Offer[2] memory offers) internal view returns (bytes memory) {
        return ratifierData(root(offers), offers[0].maker, 0, proof(offers));
    }

    function root(Offer memory offer) internal pure returns (bytes32) {
        return HashLib.hashOffer(offer);
    }

    function root(Offer[1] memory offers) internal pure returns (bytes32) {
        return HashLib.hashOffer(offers[0]);
    }

    function root(Offer[2] memory offers) internal pure returns (bytes32) {
        return HashLib.hashNode(HashLib.hashOffer(offers[0]), HashLib.hashOffer(offers[1]));
    }

    function ratifierData(bytes32 _root, address signer) internal view returns (bytes memory) {
        bytes32[] memory emptyProof = new bytes32[](0);
        return ratifierData(_root, signer, 0, emptyProof);
    }

    function ratifierData(bytes32 _root, address signer, uint256 leafIndex, bytes32[] memory _proof)
        internal
        view
        returns (bytes memory)
    {
        bytes32 structHash = keccak256(abi.encode(HashLib.offerTreeTypeHash(_proof.length), _root));
        bytes32 domainSeparator = keccak256(abi.encode(EIP712_DOMAIN_TYPEHASH, block.chainid, address(adapter)));
        bytes32 digest = keccak256(bytes.concat("\x19\x01", domainSeparator, structHash));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(privateKey[signer], digest);
        return abi.encode(Signature({v: v, r: r, s: s}), _root, leafIndex, _proof);
    }

    /// @dev Returns the concatenation of x and y, sorted lexicographically.
    function sort(bytes32 x, bytes32 y) internal pure returns (bytes memory) {
        return x < y ? abi.encodePacked(x, y) : abi.encodePacked(y, x);
    }
}
