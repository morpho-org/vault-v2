// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Morpho Association
pragma solidity ^0.8.0;

import "../lib/forge-std/src/Test.sol";
import {MidnightAdapter} from "../src/adapters/MidnightAdapter.sol";
import {MidnightAdapterFactory} from "../src/adapters/MidnightAdapterFactory.sol";
import {ERC20Mock} from "./mocks/ERC20Mock.sol";
import {OracleMock} from "../lib/morpho-blue/src/mocks/OracleMock.sol";
import {VaultV2Mock} from "./mocks/VaultV2Mock.sol";
import {IERC20} from "../src/interfaces/IERC20.sol";
import {IAdapter} from "../src/interfaces/IAdapter.sol";
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
import {maxLif, CALLBACK_SUCCESS} from "../lib/midnight/src/libraries/ConstantsLib.sol";
import {TakeAmountsLib} from "../lib/midnight/src/periphery/TakeAmountsLib.sol";
import {SetterRatifier} from "../lib/midnight/src/ratifiers/SetterRatifier.sol";

contract ExtraAssetsAdapter is IAdapter {
    uint256 public realAssets;

    function setRealAssets(uint256 newRealAssets) external {
        realAssets = newRealAssets;
    }

    function allocate(bytes memory, uint256, bytes4, address) external pure returns (bytes32[] memory, int256) {
        return (new bytes32[](0), 0);
    }

    function deallocate(bytes memory, uint256, bytes4, address) external pure returns (bytes32[] memory, int256) {
        return (new bytes32[](0), 0);
    }
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
    ExtraAssetsAdapter internal extraAssetsAdapter;

    mapping(address => uint256) internal privateKey;

    Offer storedOffer;

    uint256 internal constant MIN_TEST_ASSETS = 10;
    uint256 internal constant MAX_TEST_ASSETS = 1e24;

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
            CollateralParams({token: collToken0, lltv: 1e18, maxLif: maxLif(1e18, 0.25e18), oracle: oracle0})
        );
        storedCollaterals.push(
            CollateralParams({token: collToken1, lltv: 1e18, maxLif: maxLif(1e18, 0.25e18), oracle: oracle1})
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
            receiverIfMakerIsSeller: address(adapter),
            ratifier: address(adapter),
            reduceOnly: false,
            maxUnits: 0,
            maxAssets: 0
        });

        deal(address(loanToken), address(parentVault), 1_000_000e18);

        vm.startPrank(taker);
        IERC20(storedCollaterals[0].token).approve(address(midnight), type(uint256).max);
        IERC20(storedCollaterals[1].token).approve(address(midnight), type(uint256).max);
        deal(storedCollaterals[0].token, taker, 1_000e18);
        deal(storedCollaterals[1].token, taker, 1_000e18);
        loanToken.approve(address(midnight), type(uint256).max);
        midnight.setIsAuthorized(address(this), true, taker);
        vm.stopPrank();

        IERC20(storedCollaterals[0].token).approve(address(midnight), type(uint256).max);
        IERC20(storedCollaterals[1].token).approve(address(midnight), type(uint256).max);
        deal(storedCollaterals[0].token, address(this), 1_000_000e18);
        deal(storedCollaterals[1].token, address(this), 1_000_000e18);

        extraAssetsAdapter = new ExtraAssetsAdapter();
        address[] memory _adapters = new address[](2);
        _adapters[0] = address(adapter);
        _adapters[1] = address(extraAssetsAdapter);
        parentVault.setAdapters(_adapters);
        parentVault.setAdaptersLength(2);
    }

    /* LAST UPDATE */

    function testLastUpdate() public {
        assertEq(adapter.lastUpdate(), block.timestamp, "set at construction");
        skip(100);
        adapter.accrueInterest();
        assertEq(adapter.lastUpdate(), block.timestamp, "refreshed by accrueInterest");
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
        offer.receiverIfMakerIsSeller = address(adapter);
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

    function testRatifyInvalidProof(uint256 seed) public {
        vm.setSeed(seed);
        Offer memory offer = _ratificationSetup();
        bytes32 wrongRoot = keccak256("wrong root");
        bytes32[] memory emptyProof = new bytes32[](0);
        bytes memory data = ratifierData(wrongRoot, signerAllocator, 0, emptyProof);
        vm.expectRevert(IMidnightAdapter.InvalidProof.selector);
        adapter.isRatified(offer, data);
    }

    function testRatifySignerNotAllocator(uint256 seed) public {
        vm.setSeed(seed);
        (address otherSigner, uint256 otherSignerKey) = makeAddrAndKey("nonAllocatorSigner");
        privateKey[otherSigner] = otherSignerKey;
        vm.assume(otherSigner != signerAllocator);
        assertFalse(parentVault.isAllocator(otherSigner), "must not be allocator");

        Offer memory offer = _ratificationSetup();
        bytes32 _root = HashLib.hashOffer(offer);
        bytes memory data = ratifierData(_root, otherSigner);
        vm.expectRevert(IMidnightAdapter.IncorrectSigner.selector);
        adapter.isRatified(offer, data);
    }

    function testRatifySellOfferWithoutReduceOnly(uint256 seed) public {
        vm.setSeed(seed);
        Offer memory offer = _ratificationSetup();
        offer.buy = false;
        offer.reduceOnly = false;
        bytes32 _root = HashLib.hashOffer(offer);
        bytes memory data = ratifierData(_root, signerAllocator);
        vm.expectRevert(IMidnightAdapter.NoDebtCreation.selector);
        adapter.isRatified(offer, data);
    }

    function testRatifyReduceOnlySellAccepted(uint256 seed) public {
        vm.setSeed(seed);
        Offer memory offer = _ratificationSetup();
        offer.buy = false;
        offer.reduceOnly = true;
        bytes32 _root = HashLib.hashOffer(offer);
        bytes memory data = ratifierData(_root, signerAllocator);
        assertEq(adapter.isRatified(offer, data), CALLBACK_SUCCESS, "callback success");
    }

    function testRatifyIncorrectReceiver(uint256 seed, address otherReceiver) public {
        vm.setSeed(seed);
        vm.assume(otherReceiver != address(adapter));
        Offer memory offer = _ratificationSetup();
        offer.receiverIfMakerIsSeller = otherReceiver;
        bytes32 _root = root(offer);
        bytes memory data = ratifierData(_root, signerAllocator);
        vm.expectRevert(IMidnightAdapter.IncorrectReceiver.selector);
        adapter.isRatified(offer, data);
    }

    function testCancelRootByAllocator(uint256 seed) public {
        vm.setSeed(seed);
        Offer memory offer = _ratificationSetup();
        bytes32 _root = root(offer);
        bytes memory data = ratifierData(_root, signerAllocator);
        assertEq(adapter.isRatified(offer, data), CALLBACK_SUCCESS, "ratifies before cancel");
        vm.prank(signerAllocator);
        adapter.cancelRoot(_root);
        assertTrue(adapter.isRootCanceled(_root), "root canceled");
        vm.expectRevert(IMidnightAdapter.RootCanceled.selector);
        adapter.isRatified(offer, data);
    }

    function testCancelRootBySentinel(uint256 seed, address sentinel) public {
        vm.setSeed(seed);
        vm.assume(sentinel != signerAllocator);
        stdstore.target(address(parentVault)).sig("isSentinel(address)").with_key(sentinel).checked_write(true);
        Offer memory offer = _ratificationSetup();
        bytes32 _root = root(offer);
        bytes memory data = ratifierData(_root, signerAllocator);
        vm.prank(sentinel);
        adapter.cancelRoot(_root);
        assertTrue(adapter.isRootCanceled(_root), "root canceled");
        vm.expectRevert(IMidnightAdapter.RootCanceled.selector);
        adapter.isRatified(offer, data);
    }

    function testCancelRootUnauthorized(address caller) public {
        vm.assume(!parentVault.isAllocator(caller) && !parentVault.isSentinel(caller));
        vm.prank(caller);
        vm.expectRevert(IMidnightAdapter.NotAuthorized.selector);
        adapter.cancelRoot(keccak256("some root"));
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

    /* ALLOCATION UPDATES */

    function testExactDuration(uint32 durationIndex) public {
        durationIndex = uint32(bound(durationIndex, 0, adapter.durationsLength() - 1));
        uint256 duration = adapter.durations()[durationIndex];
        buy(duration, 1e18);
        assertEq(parentVault.allocation(durationId(duration)), 1e18);
    }

    function testExitDuration(uint256 durationIndex, uint256 timeToMaturity, uint256 extraSkip) public {
        durationIndex = bound(durationIndex, 0, adapter.durationsLength() - 1);
        uint256 duration = adapter.durations()[durationIndex];
        timeToMaturity = bound(timeToMaturity, duration, 100 * 365 days);
        extraSkip = bound(extraSkip, 1, 10 * 365 days);

        Offer memory offer = buy(timeToMaturity, 1e18);
        assertEq(parentVault.allocation(durationId(duration)), 1e18);

        skip(timeToMaturity - duration + extraSkip);

        adapter.updateDurationCountAndAllocations(offer.market);

        assertEq(parentVault.allocation(durationId(duration)), 0);
    }

    function testRepeatDeallocateExpiredDurations(uint256 durationIndex, uint256 timeToMaturity, uint256 skipAmount)
        public
    {
        durationIndex = bound(durationIndex, 0, adapter.durationsLength() - 1);
        uint256 duration = adapter.durations()[durationIndex];
        timeToMaturity = bound(timeToMaturity, duration, 100 * 365 days);
        skipAmount = bound(skipAmount, 0, duration * 2);

        Offer memory offer = buy(timeToMaturity, 1e18);
        skip(skipAmount);
        adapter.updateDurationCountAndAllocations(offer.market);
        uint256 savedAllocation = parentVault.allocation(durationId(duration));
        adapter.updateDurationCountAndAllocations(offer.market);
        assertEq(parentVault.allocation(durationId(duration)), savedAllocation);
    }

    function testUpdateOnWithdraw() public {
        Offer memory offer = buy(7 days, 1e18);
        assertEq(parentVault.allocation(durationId(1 days)), 1e18, "1 day, before");
        assertEq(parentVault.allocation(durationId(7 days)), 1e18, "7 days, before");

        skip(7 days);

        vm.prank(taker);
        midnight.repay(offer.market, 1e18, taker, address(0), "");
        vm.prank(signerAllocator);
        adapter.withdrawToVault(offer.market, 0.5e18);

        assertEq(parentVault.allocation(durationId(1 days)), 0, "1 day");
        assertEq(parentVault.allocation(durationId(7 days)), 0, "7 days");
    }

    function testUpdateOnSell() public {
        Offer memory offer = buy(7 days, 1e18);
        assertEq(parentVault.allocation(durationId(1 days)), 1e18, "1 day, before");
        assertEq(parentVault.allocation(durationId(7 days)), 1e18, "7 days, before");

        skip(1);

        parentVault.setTotalAssets(1e18);
        sell(offer.market, 0.5e18);

        assertEq(parentVault.allocation(durationId(1 days)), 0.5e18, "1 day");
        assertEq(parentVault.allocation(durationId(7 days)), 0, "7 days");
    }

    function testOnBuyRemovesAndReinsertsMaturity() public {
        buy(1 days, 1e18);
        Offer memory offer = buy(7 days, 1e18);
        buy(30 days, 1e18);
        bytes32 marketId = _marketId(offer.market);
        setMidnightCredit(marketId, address(adapter), 0);

        offer.group = bytes32("second buy");
        uint256 units = 1e18 * 1e18 / TickLib.tickToPrice(MAX_TICK);
        offer.maxUnits = units;

        vm.startPrank(taker);
        midnight.supplyCollateral(offer.market, 0, 0.5e18, taker);
        midnight.supplyCollateral(offer.market, 1, 0.5e18, taker);
        vm.stopPrank();

        offer.callbackData = hex"";
        vm.prank(taker);
        midnight.take(offer, units, taker, taker, address(0), "", sign([offer], signerAllocator));
    }

    function testSellClearsMaturityAndReactivatesSlot() public {
        Offer memory firstOffer;
        Offer memory secondOffer;
        for (uint256 i = 0; i < 50; i++) {
            Offer memory offer = buy(1 days + i, 1e18);
            if (i == 0) firstOffer = offer;
            if (i == 1) secondOffer = offer;
        }
        assertEq(adapter.pendingMaturitiesLength(), 50, "pendingMaturitiesLength before");

        parentVault.setTotalAssets(1e18);
        sell(secondOffer.market, 1e18);

        assertEq(adapter.pendingMaturitiesLength(), 49, "pendingMaturitiesLength after");
        assertEq(adapter.pendingMaturities(0), firstOffer.market.maturity, "first pending maturity after");

        buy(60 days, 1e18);

        assertEq(adapter.pendingMaturitiesLength(), 50, "pendingMaturitiesLength final");
    }

    function testUpdateOnForceDeallocate() public {
        Offer memory offer = buy(7 days, 1e18);
        assertEq(parentVault.allocation(durationId(1 days)), 1e18, "1 day, before");
        assertEq(parentVault.allocation(durationId(7 days)), 1e18, "7 days, before");

        skip(1);

        forceDeallocate(offer.market, 0.5e18);

        assertEq(parentVault.allocation(durationId(1 days)), 0.5e18, "1 day");
        assertEq(parentVault.allocation(durationId(7 days)), 0, "7 days");
    }

    /* PENDING MATURITIES */

    function testPendingMaturitiesCap(uint256 boughtNum) public {
        boughtNum = bound(boughtNum, 0, 50);
        for (uint256 i = 1; i <= boughtNum; i++) {
            buy(i, 1e18);
        }
        assertEq(adapter.pendingMaturitiesLength(), boughtNum);

        for (uint256 i = boughtNum + 1; i <= 50; i++) {
            buy(i, 1e18);
        }

        Offer memory offer = makeBuyOffer(51, 1e18, MAX_TICK);
        midnight.supplyCollateral(offer.market, 0, 0.5e18, taker);
        midnight.supplyCollateral(offer.market, 1, 0.5e18, taker);
        vm.expectRevert();
        take(offer);
    }

    function testPendingMaturitiesBuySell(uint256 boughtNum, uint256 soldNum) public {
        boughtNum = bound(boughtNum, 1, 50);
        soldNum = bound(soldNum, 0, boughtNum);

        parentVault.setTotalAssets(1e18);

        Market[] memory markets = new Market[](boughtNum);
        for (uint256 i = 0; i < boughtNum; i++) {
            markets[i] = buy(1 days + i, 1e18).market;
        }
        for (uint256 i = 0; i < soldNum; i++) {
            sell(markets[i], 1e18);
        }

        assertEq(adapter.pendingMaturitiesLength(), boughtNum - soldNum);
    }

    function testOnBuyCanRealizeLoss() public {
        uint256 tick = TickLib.priceToTick(0.95e18, 4);
        uint256 duration = 7 days;
        uint256 assets = 1e18;

        Offer memory offer = makeBuyOffer(duration, assets, tick);
        uint256 units = offer.maxUnits;
        midnight.supplyCollateral(offer.market, 0, units, taker);
        midnight.supplyCollateral(offer.market, 1, units, taker);
        take(offer);

        bytes32 marketId = _marketId(offer.market);
        uint256 loss = 0.5e18;
        stdstore.target(address(midnight)).sig("creditOf(bytes32,address)").with_key(marketId)
            .with_key(address(adapter)).checked_write(units - loss);

        offer.group = bytes32("second");
        midnight.supplyCollateral(offer.market, 0, units, taker);
        midnight.supplyCollateral(offer.market, 1, units, taker);
        take(offer);

        uint128 growth = uint128((units - assets) / duration);
        uint128 removedGrowth = uint128(uint256(growth).mulDivUp(loss, units));
        assertEq(adapter.maturities(offer.market.maturity).growth, 2 * growth - removedGrowth);
        (uint128 marketNetCredit,) = adapter._markets(marketId);
        assertEq(marketNetCredit, 2 * units - loss);
    }

    function testOnSellBufferTooLowReverts() public {
        deal(address(loanToken), address(parentVault), 1e18);
        Offer memory offer = buy(0, 1e18);
        parentVault.setTotalAssets(1e18);

        vm.expectRevert(IMidnightAdapter.BufferTooLow.selector);
        sellUnits(offer.market, 1e18, MAX_TICK - 4);
    }

    function testOnSellBufferBigEnough() public {
        uint256 loss = 1e18 - TickLib.tickToPrice(MAX_TICK - 4);

        deal(address(loanToken), address(parentVault), 1e18);
        Offer memory offer = buy(0, 1e18);
        extraAssetsAdapter.setRealAssets(loss);
        parentVault.setTotalAssets(1e18);

        sellUnits(offer.market, 1e18, MAX_TICK - 4);

        (uint128 marketNetCredit,) = adapter._markets(_marketId(offer.market));
        assertEq(marketNetCredit, 0);
        assertEq(adapter.totalAssets(), 0);
    }

    function testOutOfOrderInsertsStayTracked() public {
        uint256 t0 = block.timestamp;
        buy(3, 1e18);
        buy(1, 1e18);
        buy(2, 1e18);

        assertPendingMaturities([t0 + 3, t0 + 1, t0 + 2]);
    }

    function testMidPendingMaturityRemoval() public {
        Offer memory smallest = buy(1, 1e18);
        Offer memory middle = buy(2, 1e18);
        Offer memory largest = buy(3, 1e18);

        parentVault.setTotalAssets(1e18);
        sell(middle.market, 1e18);

        assertPendingMaturities([smallest.market.maturity, largest.market.maturity]);
    }

    function testMultipleConsecutiveElapsedMaturitiesInOneAccrual() public {
        buy(1, 1e18);
        buy(2, 1e18);
        skip(3);
        adapter.accrueInterest();
        assertPendingMaturitiesEmpty();
        assertEq(adapter.currentGrowth(), 0, "currentGrowth");
    }

    function testTwoMarketsSharingMaturity(uint256 assetsA, uint256 assetsB) public {
        assetsA = bound(assetsA, 1, 100_000e18) * 2;
        assetsB = bound(assetsB, 1, 100_000e18) * 2;

        address oracleC = address(new OracleMock());
        OracleMock(oracleC).setPrice(ORACLE_PRICE_SCALE);

        Offer memory offerA = buy(0, assetsA);

        Offer memory offerB = makeBuyOffer(0, assetsB, MAX_TICK);
        offerB.market.collateralParams[0].oracle = oracleC;
        offerB.group = bytes32("B");
        midnight.supplyCollateral(offerB.market, 0, assetsB / 2, taker);
        midnight.supplyCollateral(offerB.market, 1, assetsB / 2, taker);
        take(offerB);

        (uint128 netCreditA,) = adapter._markets(_marketId(offerA.market));
        (uint128 netCreditB,) = adapter._markets(_marketId(offerB.market));
        assertEq(netCreditA, assetsA, "netCredit A");
        assertEq(netCreditB, assetsB, "netCredit B");
        assertEq(adapter.maturities(block.timestamp).netCredit, assetsA + assetsB, "shared netCredit");
        assertEq(adapter.totalAssets(), assetsA + assetsB, "totalAssets");
    }

    function testSecondBuyAtSameMaturityDoesNotReinsert() public {
        Offer memory first = buy(7 days, 1e18);

        Offer memory second = makeBuyOffer(7 days, 1e18, MAX_TICK);
        second.group = bytes32("second");
        midnight.supplyCollateral(second.market, 0, 0.5e18, taker);
        midnight.supplyCollateral(second.market, 1, 0.5e18, taker);
        take(second);

        assertPendingMaturities([first.market.maturity]);
    }

    /* FORCE DEALLOCATE */

    function testForceDeallocateOK() public {
        Offer memory boughtOffer = buy(7 days, 1e18);
        bytes32 marketId = _marketId(boughtOffer.market);

        forceDeallocate(boughtOffer.market, 0.5e18);

        (uint128 marketNetCredit,) = adapter._markets(marketId);
        assertEq(marketNetCredit, 0.5e18);
    }

    function testForceDeallocateRevertsOnSellOffer() public {
        Offer memory boughtOffer = buy(7 days, 1e18);
        (Offer memory offer,) = makeForceDeallocateOffer(boughtOffer.market, 0.5e18);
        offer.buy = false;

        vm.expectRevert(IMidnightAdapter.IncorrectOffer.selector);
        parentVault.forceDeallocate(
            address(adapter), abi.encode(offer, abi.encode(bytes32(0), 0, proof([offer]))), 0.5e18, address(this)
        );
    }

    function testForceDeallocateRevertsOnWrongLoanToken() public {
        Offer memory boughtOffer = buy(7 days, 1e18);
        (Offer memory offer,) = makeForceDeallocateOffer(boughtOffer.market, 0.5e18);
        offer.market.loanToken = address(new ERC20Mock(18));

        vm.expectRevert(IMidnightAdapter.IncorrectOffer.selector);
        parentVault.forceDeallocate(
            address(adapter), abi.encode(offer, abi.encode(bytes32(0), 0, proof([offer]))), 0.5e18, address(this)
        );
    }

    function testForceDeallocateRevertsOnNonMaxTick() public {
        Offer memory boughtOffer = buy(7 days, 1e18);
        (Offer memory offer,) = makeForceDeallocateOffer(boughtOffer.market, 0.5e18);
        offer.tick = MAX_TICK - 1;

        vm.expectRevert(IMidnightAdapter.IncorrectOffer.selector);
        parentVault.forceDeallocate(
            address(adapter), abi.encode(offer, abi.encode(bytes32(0), 0, proof([offer]))), 0.5e18, address(this)
        );
    }

    function testForceDeallocateRevertsOnCallback() public {
        Offer memory boughtOffer = buy(7 days, 1e18);
        (Offer memory offer,) = makeForceDeallocateOffer(boughtOffer.market, 0.5e18);
        offer.callback = address(this);

        vm.expectRevert(IMidnightAdapter.IncorrectOffer.selector);
        parentVault.forceDeallocate(
            address(adapter), abi.encode(offer, abi.encode(bytes32(0), 0, proof([offer]))), 0.5e18, address(this)
        );
    }

    /* WITHDRAW TO VAULT */

    function testWithdrawToVaultUnauthorized(address nonAllocator) public {
        vm.assume(!parentVault.isAllocator(nonAllocator));
        Market memory market = storedOffer.market;
        vm.prank(nonAllocator);
        vm.expectRevert(IMidnightAdapter.NotAuthorized.selector);
        adapter.withdrawToVault(market, 0);
    }

    function testWithdrawToVaultOK() public {
        Offer memory boughtOffer = buy(7 days, 1e18);
        bytes32 marketId = _marketId(boughtOffer.market);
        (uint128 creditBefore,) = adapter._markets(marketId);
        uint256 vaultBalanceBefore = loanToken.balanceOf(address(parentVault));

        skip(7 days);

        deal(address(loanToken), address(this), 1e18);
        loanToken.approve(address(midnight), type(uint256).max);
        midnight.repay(boughtOffer.market, 1e18, taker, address(0), "");

        uint256 withdrawAmount = 0.5e18;
        vm.expectEmit(true, false, false, false, address(adapter));
        emit IMidnightAdapter.WithdrawToVault(marketId, withdrawAmount, 0);
        vm.prank(signerAllocator);
        adapter.withdrawToVault(boughtOffer.market, withdrawAmount);

        (uint128 creditAfter,) = adapter._markets(marketId);
        assertLt(creditAfter, creditBefore);
        assertEq(loanToken.balanceOf(address(parentVault)), vaultBalanceBefore + withdrawAmount);
    }

    /* SKIM */

    function testSetSkimRecipientUnauthorized(address nonOwner) public {
        vm.assume(nonOwner != owner);
        vm.prank(nonOwner);
        vm.expectRevert(IMidnightAdapter.NotAuthorized.selector);
        adapter.setSkimRecipient(recipient);
    }

    function testSetSkimRecipientOK() public {
        address newRecipient = makeAddr("newRecipient");
        vm.expectEmit(true, false, false, false, address(adapter));
        emit IMidnightAdapter.SetSkimRecipient(newRecipient);
        vm.prank(owner);
        adapter.setSkimRecipient(newRecipient);
        assertEq(adapter.skimRecipient(), newRecipient, "skimRecipient");
    }

    function testSkimUnauthorized(address caller) public {
        vm.prank(owner);
        adapter.setSkimRecipient(recipient);
        vm.assume(caller != recipient);
        vm.prank(caller);
        vm.expectRevert(IMidnightAdapter.NotAuthorized.selector);
        adapter.skim(address(rewardToken));
    }

    function testSkimOK() public {
        vm.prank(owner);
        adapter.setSkimRecipient(recipient);

        uint256 balance = 123e18;
        deal(address(rewardToken), address(adapter), balance);

        vm.expectEmit(true, false, false, true, address(adapter));
        emit IMidnightAdapter.Skim(address(rewardToken), balance);
        vm.prank(recipient);
        adapter.skim(address(rewardToken));

        assertEq(rewardToken.balanceOf(recipient), balance, "recipient received");
        assertEq(rewardToken.balanceOf(address(adapter)), 0, "adapter drained");
    }

    /* HELPERS */

    function makeBuyOffer(uint256 duration, uint256 assets, uint256 tick) internal view returns (Offer memory offer) {
        offer = storedOffer;
        offer.market.maturity = block.timestamp + duration;
        offer.buy = true;
        offer.tick = tick;
        offer.group = bytes32(duration);
        offer.maxUnits = assets * 1e18 / TickLib.tickToPrice(tick);
        offer.expiry = block.timestamp;
        offer.callback = address(adapter);
        offer.callbackData = hex"";
    }

    function take(Offer memory offer) internal {
        vm.prank(taker);
        midnight.take(offer, offer.maxUnits, taker, taker, address(0), "", sign([offer], signerAllocator));
    }

    function buy(uint256 duration, uint256 assets) internal returns (Offer memory offer) {
        offer = makeBuyOffer(duration, assets, MAX_TICK);
        midnight.supplyCollateral(offer.market, 0, assets / 2, taker);
        midnight.supplyCollateral(offer.market, 1, assets / 2, taker);
        take(offer);
    }

    function makeSellOffer(Market memory market, uint256 units, uint256 tick)
        internal
        view
        returns (Offer memory offer)
    {
        offer = storedOffer;
        offer.market = market;
        offer.buy = false;
        offer.reduceOnly = true;
        offer.tick = tick;
        offer.maxUnits = units;
        offer.expiry = block.timestamp;
        offer.callback = address(adapter);
        offer.receiverIfMakerIsSeller = address(adapter);
        offer.group = bytes32(vm.randomUint());
        offer.callbackData = hex"";
    }

    function sell(Market memory market, uint256 assets) internal {
        Offer memory offer = makeSellOffer(market, 0, MAX_TICK);
        offer.maxUnits = TakeAmountsLib.sellerAssetsToUnits(address(midnight), _marketId(market), offer, assets);
        vm.prank(taker);
        midnight.take(offer, offer.maxUnits, taker, taker, address(0), "", sign([offer], signerAllocator));
    }

    function sellUnits(Market memory market, uint256 units, uint256 tick) internal {
        Offer memory offer = makeSellOffer(market, units, tick);
        vm.prank(taker);
        midnight.take(offer, offer.maxUnits, taker, taker, address(0), "", sign([offer], signerAllocator));
    }

    function makeForceDeallocateOffer(Market memory market, uint256 assets)
        internal
        returns (Offer memory offer, bytes32 root_)
    {
        address buyer = makeAddr("buyer");
        SetterRatifier approvalRatifier = new SetterRatifier(address(midnight));

        offer = storedOffer;
        offer.market = market;
        offer.buy = true;
        offer.maker = buyer;
        offer.tick = MAX_TICK;
        uint256 price = TickLib.tickToPrice(MAX_TICK);
        uint256 units = assets * 1e18 / price;
        offer.maxUnits = units;
        offer.expiry = block.timestamp;
        offer.callback = address(0);
        offer.callbackData = hex"";
        offer.ratifier = address(approvalRatifier);
        offer.group = bytes32(vm.randomUint());

        deal(address(loanToken), buyer, assets);
        vm.startPrank(buyer);
        loanToken.approve(address(midnight), type(uint256).max);
        midnight.setIsAuthorized(address(approvalRatifier), true, buyer);
        root_ = root([offer]);
        approvalRatifier.setIsRootRatified(buyer, root_, true);
        vm.stopPrank();
    }

    function forceDeallocate(Market memory market, uint256 assets) internal {
        (Offer memory offer, bytes32 root_) = makeForceDeallocateOffer(market, assets);
        bytes memory data = abi.encode(offer, abi.encode(root_, 0, proof([offer])));
        parentVault.forceDeallocate(address(adapter), data, assets, address(this));
    }

    function durationId(uint256 duration) internal pure returns (bytes32) {
        return keccak256(abi.encode("duration", duration));
    }

    function setMidnightCredit(bytes32 marketId, address account, uint256 credit) internal {
        stdstore.target(address(midnight)).sig("creditOf(bytes32,address)").with_key(marketId).with_key(account)
            .checked_write(credit);
    }

    function checkPendingMaturities(uint256[] memory expected) internal view {
        uint256 length = adapter.pendingMaturitiesLength();
        assertEq(length, expected.length, "pendingMaturitiesLength");
        for (uint256 i = 0; i < expected.length; i++) {
            uint48 maturity = expected[i].toUint48();
            bool found;
            for (uint256 j = 0; j < length; j++) {
                found = found || adapter.pendingMaturities(j) == maturity;
            }
            assertTrue(found, "missing pending maturity");
            uint256 index = adapter.maturities(maturity).index;
            assertLt(index, length, "index out of bounds");
            assertEq(adapter.pendingMaturities(index), maturity, "pendingMaturities[index] matches");
        }
    }

    function assertPendingMaturitiesEmpty() internal view {
        checkPendingMaturities(new uint256[](0));
    }

    function assertPendingMaturities(uint256[1] memory m) internal view {
        uint256[] memory arr = new uint256[](1);
        arr[0] = m[0];
        checkPendingMaturities(arr);
    }

    function assertPendingMaturities(uint256[2] memory m) internal view {
        uint256[] memory arr = new uint256[](2);
        arr[0] = m[0];
        arr[1] = m[1];
        checkPendingMaturities(arr);
    }

    function assertPendingMaturities(uint256[3] memory m) internal view {
        uint256[] memory arr = new uint256[](3);
        arr[0] = m[0];
        arr[1] = m[1];
        arr[2] = m[2];
        checkPendingMaturities(arr);
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
