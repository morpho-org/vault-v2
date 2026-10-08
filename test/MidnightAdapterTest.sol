// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Morpho Association
pragma solidity ^0.8.0;

import "../lib/forge-std/src/Test.sol";
import {MidnightAdapterFactory} from "../src/adapters/MidnightAdapterFactory.sol";
import {ERC20Mock} from "./mocks/ERC20Mock.sol";
import {OracleMock} from "../lib/morpho-blue/src/mocks/OracleMock.sol";
import {VaultV2Mock} from "./mocks/VaultV2Mock.sol";
import {AdapterMock} from "./mocks/AdapterMock.sol";
import {IERC20} from "../src/interfaces/IERC20.sol";
import {IAdapter} from "../src/interfaces/IAdapter.sol";
import {IMidnightAdapter, IMidnightAdapterBase, MarketData} from "../src/adapters/interfaces/IMidnightAdapter.sol";
import {MidnightAdapterPriceRatifierV1} from "../src/adapters/ratifiers/MidnightAdapterPriceRatifierV1.sol";
import {
    IMidnightAdapterPriceRatifierV1
} from "../src/adapters/ratifiers/interfaces/IMidnightAdapterPriceRatifierV1.sol";
import {IVaultV2} from "../src/interfaces/IVaultV2.sol";
import {ISendSharesGate} from "../src/interfaces/IGate.sol";
import {ErrorsLib} from "../src/libraries/ErrorsLib.sol";
import {IMidnightAdapterFactory} from "../src/adapters/interfaces/IMidnightAdapterFactory.sol";
import {MathLib} from "../src/libraries/MathLib.sol";
import {IMidnight, Offer, Market, CollateralParams} from "../lib/midnight/src/interfaces/IMidnight.sol";
import {HashLib} from "../lib/midnight/src/ratifiers/libraries/HashLib.sol";
import {TickLib, MAX_TICK} from "../lib/midnight/src/libraries/TickLib.sol";
import {IdLib} from "../lib/midnight/src/libraries/IdLib.sol";
import {stdStorage, StdStorage} from "../lib/forge-std/src/Test.sol";
import {ORACLE_PRICE_SCALE} from "../lib/morpho-blue/src/libraries/ConstantsLib.sol";
import {
    CALLBACK_SUCCESS,
    DEFAULT_TICK_SPACING,
    MAX_CONTINUOUS_FEE,
    MAX_SETTLEMENT_FEE_0_DAYS,
    CBP
} from "../lib/midnight/src/libraries/ConstantsLib.sol";
import {TakeAmountsLib} from "../lib/midnight/src/periphery/libraries/TakeAmountsLib.sol";
import {IEnterGate} from "../lib/midnight/src/interfaces/IGate.sol";

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

/// @notice Realizes the losses of a midnight adapter in a market.
contract GarbageSubRatifier {
    function isRatified(Offer memory, bytes memory, address) external pure returns (bytes32) {
        return bytes32(uint256(1));
    }
}

contract EagerLossCallback {
    struct Action {
        address target;
        bytes data;
        bytes4 expectedRevert;
    }

    address internal immutable midnight;
    Action[] internal actions;

    constructor(address midnight_, address token, address vault) {
        midnight = midnight_;
        IERC20(token).approve(midnight_, type(uint256).max);
        IERC20(token).approve(vault, type(uint256).max);
        IMidnight(midnight_).setIsAuthorized(msg.sender, true, address(this));
    }

    function push(address target, bytes memory data, bytes4 expectedRevert) external {
        actions.push(Action(target, data, expectedRevert));
    }

    function onBuy(bytes32, Market memory, uint256, uint256, uint256, address, bytes memory)
        external
        returns (bytes32)
    {
        require(msg.sender == midnight);
        for (uint256 i; i < actions.length; i++) {
            Action storage action = actions[i];
            (bool success, bytes memory result) = action.target.call(action.data);
            if (action.expectedRevert == bytes4(0)) {
                if (!success) {
                    assembly ("memory-safe") {
                        revert(add(result, 32), mload(result))
                    }
                }
            } else {
                require(!success, "expected callback action to revert");
                require(result.length >= 4 && bytes4(result) == action.expectedRevert, "wrong callback revert");
            }
        }
        return CALLBACK_SUCCESS;
    }
}

contract MidnightAdapterTest is Test {
    using stdStorage for StdStorage;
    using MathLib for uint256;

    IMidnight internal midnight;
    IMidnightAdapterFactory internal factory;
    IMidnightAdapter internal adapter;
    MidnightAdapterPriceRatifierV1 internal priceRatifier;
    VaultV2Mock internal parentVault;
    IVaultV2 internal realVault;
    IERC20 internal loanToken;
    IERC20 internal rewardToken;
    address internal owner;
    address internal curator;
    address internal signerAllocator;
    address internal taker;
    address internal recipient;
    address internal tradingFeeRecipient = makeAddr("tradingFeeRecipient");
    CollateralParams[] internal storedCollaterals;
    CollateralParams[] internal storedSingleCollateral;
    ExtraAssetsAdapter internal extraAssetsAdapter;

    Offer storedOffer;

    uint256 internal constant MIN_TEST_ASSETS = 10;
    uint256 internal constant MAX_TEST_ASSETS = 1e24;

    uint256[] internal allDurations = [1 days, 7 days, 30 days, 90 days, 180 days];
    uint256 internal discountTick = TickLib.priceToTick(0.95e18, DEFAULT_TICK_SPACING);

    function setUp() public virtual {
        vm.setEvmVersion("osaka");
        owner = makeAddr("owner");
        curator = makeAddr("curator");
        signerAllocator = makeAddr("signerAllocator");

        recipient = makeAddr("recipient");
        taker = makeAddr("taker");

        // Deployed from the artifact so the test unit does not compile Midnight (see foundry.toml).
        midnight = IMidnight(deployCode("Midnight.sol:Midnight"));
        midnight.enableLltv(1e18);
        midnight.enableLiquidationCursor(0.25e18);
        midnight.setFeeSetter(address(this));

        loanToken = IERC20(address(new ERC20Mock(18)));
        rewardToken = IERC20(address(new ERC20Mock(18)));

        parentVault = new VaultV2Mock(address(loanToken), owner, curator, signerAllocator, address(0));

        factory = new MidnightAdapterFactory(address(midnight), allDurations);
        adapter = IMidnightAdapter(factory.createMidnightAdapter(address(parentVault)));
        setShortfallParams(0.005e18, 1 days);
        disableDurationCaps(adapter);
        setUpMaxTtm(type(uint32).max);

        priceRatifier = new MidnightAdapterPriceRatifierV1();
        addSubRatifier(adapter, address(priceRatifier));

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
            CollateralParams({token: collToken0, lltv: 1e18, liquidationCursor: 0.25e18, oracle: oracle0})
        );
        storedCollaterals.push(
            CollateralParams({token: collToken1, lltv: 1e18, liquidationCursor: 0.25e18, oracle: oracle1})
        );

        OracleMock(storedCollaterals[0].oracle).setPrice(ORACLE_PRICE_SCALE);
        OracleMock(storedCollaterals[1].oracle).setPrice(ORACLE_PRICE_SCALE);

        storedSingleCollateral.push(storedCollaterals[0]);

        uint256 maturity = vm.getBlockTimestamp() + 200;
        storedOffer = Offer({
            market: Market({
                chainId: block.chainid,
                midnight: address(midnight),
                loanToken: address(loanToken),
                collateralParams: storedCollaterals,
                maturity: maturity,
                rcfThreshold: 0,
                enterGate: address(0),
                liquidatorGate: address(0)
            }),
            buy: true,
            maker: address(adapter),
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
            maxAssets: 0,
            continuousFeeCap: type(uint256).max
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

    /* EMPTY ADAPTER */

    function testEmptyAdapter() public {
        assertEq(adapter.realAssets(), 0, "realAssets");
        assertEq(adapter.marketIdsLength(), 0, "marketIdsLength");
        assertEq(adapter.MAX_MARKETS(), 250, "MAX_MARKETS");
        skip(100);
        assertEq(adapter.realAssets(), 0, "realAssets after time passes");
    }

    /* GETTERS */

    function testGetEmptyData(bytes32 marketId) public view {
        MarketData memory marketData = adapter.marketData(marketId);
        assertEq(marketData.netCredit, 0, "market netCredit");
        assertEq(marketData.growth, 0, "growth");
        assertEq(marketData.maturity, 0, "maturity");
        assertEq(marketData.index, 0, "index");
        assertEq(marketData.totalShares, 0, "total shares");
        assertEq(marketData.vaultShares, 0, "vault shares");
    }

    function testGetMarketData() public {
        Offer memory first = buy(1 days, 1e18);
        uint256 balanceBefore = loanToken.balanceOf(address(parentVault));
        Offer memory second = buy(7 days, 1e18, discountTick);
        uint256 paidAssets = balanceBefore - loanToken.balanceOf(address(parentVault));

        MarketData memory marketData = adapter.marketData(_marketId(second.market));
        assertEq(marketData.netCredit, second.maxUnits, "netCredit");
        assertEq(marketData.growth, (second.maxUnits - paidAssets) * 1e18 / 7 days / second.maxUnits, "growth");
        assertEq(marketData.maturity, second.market.maturity, "maturity");
        assertEq(marketData.index, 1, "index");
        assertEq(marketData.totalShares, uint256(second.maxUnits) * 1e9, "total shares");
        assertEq(marketData.vaultShares, marketData.totalShares, "vault shares");

        sell(first.market, 1e18);
        assertEq(adapter.marketData(_marketId(second.market)).index, 0, "updated index");
    }

    /* TIMELOCKS */

    function testSubmit(address caller) public {
        vm.assume(caller != curator);
        bytes memory data = abi.encodeCall(IMidnightAdapterBase.setSkimRecipient, (recipient));

        vm.prank(caller);
        vm.expectRevert(IMidnightAdapterBase.NotAuthorized.selector);
        adapter.submit(data);

        vm.expectEmit(address(adapter));
        emit IMidnightAdapterBase.Submit(IMidnightAdapterBase.setSkimRecipient.selector, data, block.timestamp);
        vm.prank(curator);
        adapter.submit(data);
        assertEq(adapter.executableAt(data), block.timestamp, "executableAt");

        vm.prank(curator);
        vm.expectRevert(IMidnightAdapterBase.DataAlreadyPending.selector);
        adapter.submit(data);
    }

    function testRevoke(address caller) public {
        address sentinel = makeAddr("timelockSentinel");
        stdstore.target(address(parentVault)).sig("isSentinel(address)").with_key(sentinel).checked_write(true);
        vm.assume(caller != curator && !parentVault.isSentinel(caller));
        bytes memory data = abi.encodeCall(IMidnightAdapterBase.setSkimRecipient, (recipient));

        vm.prank(sentinel);
        vm.expectRevert(IMidnightAdapterBase.DataNotTimelocked.selector);
        adapter.revoke(data);

        vm.prank(curator);
        adapter.submit(data);

        vm.prank(caller);
        vm.expectRevert(IMidnightAdapterBase.NotAuthorized.selector);
        adapter.revoke(data);

        uint256 snapshot = vm.snapshotState();
        vm.expectEmit(address(adapter));
        emit IMidnightAdapterBase.Revoke(curator, IMidnightAdapterBase.setSkimRecipient.selector, data);
        vm.prank(curator);
        adapter.revoke(data);
        assertEq(adapter.executableAt(data), 0, "revoked by curator");

        vm.revertToStateAndDelete(snapshot);
        vm.expectEmit(address(adapter));
        emit IMidnightAdapterBase.Revoke(sentinel, IMidnightAdapterBase.setSkimRecipient.selector, data);
        vm.prank(sentinel);
        adapter.revoke(data);
        assertEq(adapter.executableAt(data), 0, "revoked by sentinel");
    }

    function testIncreaseAndDecreaseTimelock(uint256 oldDuration, uint256 newDuration) public {
        oldDuration = bound(oldDuration, 1, 3650 days);
        newDuration = bound(newDuration, 0, oldDuration);
        bytes4 selector = IMidnightAdapterBase.setSkimRecipient.selector;

        bytes memory increaseData = abi.encodeCall(IMidnightAdapterBase.increaseTimelock, (selector, oldDuration));
        vm.prank(curator);
        adapter.submit(increaseData);
        vm.expectEmit(address(adapter));
        emit IMidnightAdapterBase.Accept(IMidnightAdapterBase.increaseTimelock.selector, increaseData);
        vm.expectEmit(address(adapter));
        emit IMidnightAdapterBase.IncreaseTimelock(selector, oldDuration);
        adapter.increaseTimelock(selector, oldDuration);
        assertEq(adapter.timelock(selector), oldDuration, "increased timelock");

        bytes memory invalidIncreaseData =
            abi.encodeCall(IMidnightAdapterBase.increaseTimelock, (selector, oldDuration - 1));
        vm.prank(curator);
        adapter.submit(invalidIncreaseData);
        vm.expectRevert(IMidnightAdapterBase.TimelockNotIncreasing.selector);
        adapter.increaseTimelock(selector, oldDuration - 1);

        bytes memory invalidDecreaseData =
            abi.encodeCall(IMidnightAdapterBase.decreaseTimelock, (selector, oldDuration + 1));
        vm.prank(curator);
        adapter.submit(invalidDecreaseData);
        assertEq(adapter.executableAt(invalidDecreaseData), block.timestamp + oldDuration, "invalid decrease delay");
        skip(oldDuration);
        vm.expectRevert(IMidnightAdapterBase.TimelockNotDecreasing.selector);
        adapter.decreaseTimelock(selector, oldDuration + 1);

        bytes memory decreaseData = abi.encodeCall(IMidnightAdapterBase.decreaseTimelock, (selector, newDuration));
        vm.prank(curator);
        adapter.submit(decreaseData);
        assertEq(adapter.executableAt(decreaseData), block.timestamp + oldDuration, "decrease delay");
        skip(oldDuration);
        vm.expectEmit(address(adapter));
        emit IMidnightAdapterBase.Accept(IMidnightAdapterBase.decreaseTimelock.selector, decreaseData);
        vm.expectEmit(address(adapter));
        emit IMidnightAdapterBase.DecreaseTimelock(selector, newDuration);
        adapter.decreaseTimelock(selector, newDuration);
        assertEq(adapter.timelock(selector), newDuration, "decreased timelock");
    }

    function testCannotSetDecreaseTimelock() public {
        bytes4 selector = IMidnightAdapterBase.decreaseTimelock.selector;
        bytes memory increaseData = abi.encodeCall(IMidnightAdapterBase.increaseTimelock, (selector, 1 days));
        vm.prank(curator);
        adapter.submit(increaseData);
        vm.expectRevert(IMidnightAdapterBase.AutomaticallyTimelocked.selector);
        adapter.increaseTimelock(selector, 1 days);

        bytes memory decreaseData = abi.encodeCall(IMidnightAdapterBase.decreaseTimelock, (selector, 0));
        vm.prank(curator);
        adapter.submit(decreaseData);
        vm.expectRevert(IMidnightAdapterBase.AutomaticallyTimelocked.selector);
        adapter.decreaseTimelock(selector, 0);

        assertEq(adapter.timelock(selector), 0, "decreaseTimelock timelock");
    }

    function testTimelockedCall(uint256 duration) public {
        duration = bound(duration, 1, 3650 days);
        submitTimelock(IMidnightAdapterBase.setSkimRecipient.selector, duration);

        bytes memory data = abi.encodeCall(IMidnightAdapterBase.setSkimRecipient, (recipient));
        vm.prank(curator);
        adapter.submit(data);

        skip(duration - 1);
        vm.expectRevert(IMidnightAdapterBase.TimelockNotExpired.selector);
        adapter.setSkimRecipient(recipient);

        skip(1);
        vm.expectEmit(address(adapter));
        emit IMidnightAdapterBase.Accept(IMidnightAdapterBase.setSkimRecipient.selector, data);
        adapter.setSkimRecipient(recipient);
        assertEq(adapter.skimRecipient(), recipient, "skimRecipient");
        assertEq(adapter.executableAt(data), 0, "executableAt");

        vm.expectRevert(IMidnightAdapterBase.DataNotTimelocked.selector);
        adapter.setSkimRecipient(recipient);
    }

    function testAbdicate() public {
        bytes4 selector = IMidnightAdapterBase.setSkimRecipient.selector;
        vm.expectRevert(IMidnightAdapterBase.DataNotTimelocked.selector);
        adapter.abdicate(selector);

        bytes memory abdicateData = abi.encodeCall(IMidnightAdapterBase.abdicate, (selector));
        vm.prank(curator);
        adapter.submit(abdicateData);
        vm.expectEmit(address(adapter));
        emit IMidnightAdapterBase.Accept(IMidnightAdapterBase.abdicate.selector, abdicateData);
        vm.expectEmit(address(adapter));
        emit IMidnightAdapterBase.Abdicate(selector);
        adapter.abdicate(selector);
        assertTrue(adapter.abdicated(selector), "abdicated");

        bytes memory data = abi.encodeCall(IMidnightAdapterBase.setSkimRecipient, (recipient));
        vm.prank(curator);
        adapter.submit(data);
        vm.expectRevert(IMidnightAdapterBase.Abdicated.selector);
        adapter.setSkimRecipient(recipient);
    }

    /* MAX SELL RATE */

    function testMaxSellRateDefault(bytes32 collateralParamsHash) public view {
        assertEq(adapter.maxSellRate(collateralParamsHash), 0);
    }

    function testSetMaxSellRateAuthorized(uint256 oldMaxSellRate, uint256 newMaxSellRate) public {
        bytes32 collateralParamsHash = keccak256(abi.encode(storedOffer.market.collateralParams));
        vm.prank(curator);
        adapter.setMaxSellRate(collateralParamsHash, oldMaxSellRate);
        vm.expectEmit(address(adapter));
        emit IMidnightAdapterBase.SetMaxSellRate(curator, collateralParamsHash, newMaxSellRate);
        vm.prank(curator);
        adapter.setMaxSellRate(collateralParamsHash, newMaxSellRate);
        assertEq(adapter.maxSellRate(collateralParamsHash), newMaxSellRate, "maximum updated immediately");
    }

    function testSetMaxSellRateNotAuthorized(address caller, bool sentinel) public {
        vm.assume(caller != curator);
        if (sentinel) {
            stdstore.target(address(parentVault)).sig("isSentinel(address)").with_key(caller).checked_write(true);
        }
        vm.expectRevert(IMidnightAdapterBase.NotAuthorized.selector);
        vm.prank(caller);
        adapter.setMaxSellRate(bytes32(0), 1e18);
    }

    function testSetMaxSellRateCanIncreaseDecreaseAndClear() public {
        bytes32 collateralParamsHash = keccak256(abi.encode(storedOffer.market.collateralParams));
        setMaxSellRate(storedOffer.market, 0.5e18);
        assertEq(adapter.maxSellRate(collateralParamsHash), 0.5e18);

        setMaxSellRate(storedOffer.market, 0.4e18);
        assertEq(adapter.maxSellRate(collateralParamsHash), 0.4e18);

        setMaxSellRate(storedOffer.market, 0.6e18);
        assertEq(adapter.maxSellRate(collateralParamsHash), 0.6e18);

        setMaxSellRate(storedOffer.market, 0);
        assertEq(adapter.maxSellRate(collateralParamsHash), 0);
    }

    /* MIN RATE */

    function testSetMinBuyRateNotAuthorized(address caller, uint256 newMinBuyRate) public {
        vm.assume(caller != curator);
        vm.expectRevert(IMidnightAdapterBase.NotAuthorized.selector);
        vm.prank(caller);
        adapter.setMinBuyRate(newMinBuyRate);
    }

    function testSetMinBuyRateAuthorized(uint256 oldMinBuyRate, uint256 newMinBuyRate) public {
        oldMinBuyRate = bound(oldMinBuyRate, 0, type(uint64).max);
        newMinBuyRate = bound(newMinBuyRate, 0, type(uint64).max);
        vm.prank(curator);
        adapter.setMinBuyRate(oldMinBuyRate);
        vm.expectEmit(address(adapter));
        emit IMidnightAdapterBase.SetMinBuyRate(newMinBuyRate);
        vm.prank(curator);
        adapter.setMinBuyRate(newMinBuyRate);
        assertEq(adapter.minBuyRate(), newMinBuyRate, "minBuyRate");
    }

    function testSetMinBuyRateOverflow(uint256 newMinBuyRate) public {
        newMinBuyRate = bound(newMinBuyRate, uint256(type(uint64).max) + 1, type(uint256).max);
        vm.expectRevert(ErrorsLib.CastOverflow.selector);
        vm.prank(curator);
        adapter.setMinBuyRate(newMinBuyRate);
    }

    function testSetMinBuyRateDecrease(uint256 oldMinBuyRate, uint256 newMinBuyRate) public {
        oldMinBuyRate = bound(oldMinBuyRate, 0, type(uint64).max);
        newMinBuyRate = bound(newMinBuyRate, 0, oldMinBuyRate);
        setMinBuyRate(oldMinBuyRate);
        setMinBuyRate(newMinBuyRate);
        assertEq(adapter.minBuyRate(), newMinBuyRate, "minBuyRate decreased");
    }

    function testMinBuyRateRejectsPreviouslyRatifiedZeroRateOffer() public {
        Offer memory offer = makeBuyOffer(30 days, 1e18, MAX_TICK);
        midnight.supplyCollateral(offer.market, 0, offer.maxUnits, taker);
        bytes memory data = ratify([offer], signerAllocator);
        assertEq(adapter.minBuyRate(), 0, "default minBuyRate");
        setMinBuyRate(1);

        vm.prank(taker);
        vm.expectRevert(IMidnightAdapterBase.BuyRateTooLow.selector);
        midnight.take(offer, data, offer.maxUnits, taker, taker, address(0), "");
        assertEq(adapter.realAssets(), 0, "failed buy leaves no assets");
        assertEq(midnight.consumed(address(adapter), offer.group), 0, "offer not consumed");

        setMinBuyRate(0);
        take(offer);
        assertEq(adapter.marketData(_marketId(offer.market)).netCredit, offer.maxUnits, "zero rate accepted");
    }

    function testMinBuyRateBoundary(uint256 duration, uint256 assets, uint256 continuousFee) public {
        duration = bound(duration, 1, 365 days);
        assets = bound(assets, MIN_TEST_ASSETS, MAX_TEST_ASSETS);
        continuousFee = bound(continuousFee, 0, MAX_CONTINUOUS_FEE);
        midnight.setDefaultContinuousFee(address(loanToken), continuousFee);
        Offer memory offer = makeBuyOffer(duration, assets, discountTick);
        midnight.supplyCollateral(offer.market, 0, offer.maxUnits / 2, taker);
        midnight.supplyCollateral(offer.market, 1, offer.maxUnits - offer.maxUnits / 2, taker);
        uint256 paidAssets = uint256(offer.maxUnits).mulDivDown(TickLib.tickToPrice(offer.tick), 1e18);
        uint256 pendingFee = uint256(offer.maxUnits).mulDivDown(continuousFee * duration, 1e18);
        uint256 netCredit = offer.maxUnits - pendingFee;
        uint256 rate = (netCredit - paidAssets) * 1e18 / (paidAssets * duration);
        setMinBuyRate(rate + 1);

        vm.expectRevert(IMidnightAdapterBase.BuyRateTooLow.selector);
        take(offer);

        setMinBuyRate(rate);
        take(offer);
        assertEq(adapter.marketData(_marketId(offer.market)).netCredit, netCredit, "net rate accepted");
    }

    function testMinBuyRateUsesRemainingDuration() public {
        Offer memory offer = makeBuyOffer(30 days, 1e18, discountTick);
        offer.expiry = offer.market.maturity;
        midnight.supplyCollateral(offer.market, 0, offer.maxUnits, taker);
        uint256 paidAssets = uint256(offer.maxUnits).mulDivDown(TickLib.tickToPrice(offer.tick), 1e18);
        uint256 rate = (offer.maxUnits - paidAssets) * 1e18 / (paidAssets * 15 days);
        setMinBuyRate(rate);

        vm.expectRevert(IMidnightAdapterBase.BuyRateTooLow.selector);
        take(offer);

        skip(15 days);
        take(offer);
        assertEq(adapter.marketData(_marketId(offer.market)).netCredit, offer.maxUnits, "remaining duration used");
    }

    function testMinBuyRateZeroPaidAssets() public {
        Offer memory offer = makeBuyOffer(30 days, 1e18, MAX_TICK);
        offer.tick = 0;
        midnight.supplyCollateral(offer.market, 0, offer.maxUnits, taker);
        setMinBuyRate(type(uint64).max);
        uint256 balanceBefore = loanToken.balanceOf(address(parentVault));

        take(offer);

        assertEq(loanToken.balanceOf(address(parentVault)), balanceBefore, "no assets paid");
        assertEq(adapter.marketData(_marketId(offer.market)).netCredit, offer.maxUnits, "free credit accepted");
    }

    function testMinBuyRateAtMaturity() public {
        setMinBuyRate(type(uint64).max);
        Offer memory offer = buy(0, 1e18);
        assertEq(adapter.marketData(_marketId(offer.market)).netCredit, offer.maxUnits, "matured credit accepted");
    }

    function testMinBuyRateDoesNotRestrictSells() public {
        Offer memory offer = buy(30 days, 1e18);
        setMinBuyRate(type(uint64).max);
        sell(offer.market, offer.maxUnits);
        assertEq(adapter.marketData(_marketId(offer.market)).netCredit, 0, "sell accepted");
    }

    /// forge-config: default.isolate = true
    function testMinBuyRateAllocatorTakeRealVault() public {
        setUpRealVault();
        Market memory market = makeBuyOffer(7 days, 1e18, MAX_TICK).market;
        Offer memory offer = makeExternalOffer(market, false, 1e18, MAX_TICK);
        setMinBuyRate(1);

        vm.prank(signerAllocator);
        vm.expectRevert(IMidnightAdapterBase.BuyRateTooLow.selector);
        adapter.take(offer, "", offer.maxUnits);
        assertEq(realVault.allocation(adapter.adapterId()), 0, "failed buy leaves no allocation");
        assertEq(loanToken.balanceOf(address(realVault)), 10e18, "failed buy leaves vault funds unchanged");

        setMinBuyRate(0);
        vm.prank(signerAllocator);
        adapter.take(offer, "", offer.maxUnits);
        assertEq(realVault.allocation(adapter.adapterId()), 1e18, "buy accepted");
    }

    /// forge-config: default.isolate = true
    function testMinBuyRateAllocatorTakeNetRate() public {
        setUpRealVault();
        uint256 duration = 7 days;
        midnight.setDefaultContinuousFee(address(loanToken), MAX_CONTINUOUS_FEE);
        for (uint256 i = 0; i <= 6; i++) {
            midnight.setDefaultSettlementFee(address(loanToken), i, 10 * CBP);
        }
        Market memory market = makeBuyOffer(duration, 1e18, MAX_TICK).market;
        Offer memory offer = makeExternalOffer(market, false, 1e18, discountTick);
        midnight.supplyCollateral(market, 0, offer.maxUnits - 1e18, offer.maker);
        bytes32 marketId = _marketId(market);
        uint256 buyerPrice = TickLib.tickToPrice(offer.tick) + midnight.settlementFee(marketId, duration);
        uint256 paidAssets = uint256(offer.maxUnits).mulDivUp(buyerPrice, 1e18);
        uint256 pendingFee = uint256(offer.maxUnits).mulDivDown(uint256(MAX_CONTINUOUS_FEE) * duration, 1e18);
        uint256 netCredit = offer.maxUnits - pendingFee;
        uint256 rate = (netCredit - paidAssets) * 1e18 / (paidAssets * duration);
        setMinBuyRate(rate + 1);

        vm.prank(signerAllocator);
        vm.expectRevert(IMidnightAdapterBase.BuyRateTooLow.selector);
        adapter.take(offer, "", offer.maxUnits);

        setMinBuyRate(rate);
        vm.prank(signerAllocator);
        adapter.take(offer, "", offer.maxUnits);
        assertEq(adapter.marketData(marketId).netCredit, netCredit, "net rate accepted");
        assertEq(loanToken.balanceOf(address(realVault)), 10e18 - paidAssets, "includes settlement fee");
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
            collateralParams[i] =
                CollateralParams({token: tokens[i], lltv: 1 ether, liquidationCursor: 0.25e18, oracle: oracles[i]});
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

    function testRatifyLoanAssetMismatch(uint256 seed, address otherToken) public {
        vm.setSeed(seed);
        Offer memory offer = _ratificationSetup();
        vm.assume(otherToken != offer.market.loanToken);
        offer.market.loanToken = otherToken;
        bytes32 _root = root(offer);
        bytes memory data = ratifierData(_root, signerAllocator);
        vm.expectRevert(IMidnightAdapterBase.LoanAssetMismatch.selector);
        adapter.isRatified(offer, data, taker);
    }

    function testRatifyIncorrectMaker(uint256 seed, address otherMaker) public {
        vm.setSeed(seed);
        Offer memory offer = _ratificationSetup();
        vm.assume(otherMaker != address(adapter));
        offer.maker = otherMaker;
        bytes32 _root = root(offer);
        bytes memory data = ratifierData(_root, signerAllocator);
        vm.expectRevert(IMidnightAdapterBase.IncorrectMaker.selector);
        adapter.isRatified(offer, data, taker);
    }

    function testRatifyOtherAdapterAllocator(uint256 seed) public {
        vm.setSeed(seed);
        address otherAllocator = makeAddr("otherAllocator");
        VaultV2Mock otherVault = new VaultV2Mock(address(loanToken), owner, curator, otherAllocator, address(0));
        address otherAdapter = factory.createMidnightAdapter(address(otherVault));
        Offer memory offer = _ratificationSetup();
        offer.maker = otherAdapter;
        bytes32 _root = root(offer);
        vm.prank(signerAllocator);
        vm.expectRevert(IMidnightAdapterPriceRatifierV1.Unauthorized.selector);
        priceRatifier.setIsRootRatified(otherAdapter, _root, true);
        vm.prank(otherAllocator);
        priceRatifier.setIsRootRatified(otherAdapter, _root, true);
        bytes memory data = abi.encode(_root, uint256(0), proof([offer]), address(0));
        assertEq(priceRatifier.isRatified(offer, data, taker), CALLBACK_SUCCESS);
    }

    function testRatifyIncorrectCallbackAddress(uint256 seed) public {
        vm.setSeed(seed);
        Offer memory offer = _ratificationSetup();
        offer.callback = address(0);
        bytes32 _root = root(offer);
        bytes memory data = ratifierData(_root, signerAllocator);
        vm.expectRevert(IMidnightAdapterBase.IncorrectCallbackAddress.selector);
        adapter.isRatified(offer, data, taker);
    }

    function testRatifyOK(uint256 seed) public {
        vm.setSeed(seed);
        Offer memory offer = _ratificationSetup();
        bytes32 _root = root(offer);
        bytes memory data = ratifierData(_root, signerAllocator);
        assertEq(adapter.isRatified(offer, data, taker), CALLBACK_SUCCESS, "callback success");
    }

    function testRatifyTwoOfferTree(uint256 seed) public {
        vm.setSeed(seed);
        Offer memory offer = _ratificationSetup();
        Offer memory sibling = _ratificationSetup();
        bytes32 _root = root([offer, sibling]);

        bytes memory data = ratifierData(_root, signerAllocator, 0, proof([offer, sibling]));
        assertEq(adapter.isRatified(offer, data, taker), CALLBACK_SUCCESS, "first leaf");

        bytes32[] memory siblingProof = new bytes32[](1);
        siblingProof[0] = HashLib.hashPriceRatifierV1Offer(offer, address(0));
        data = ratifierData(_root, signerAllocator, 1, siblingProof);
        assertEq(adapter.isRatified(sibling, data, taker), CALLBACK_SUCCESS, "second leaf");

        data = ratifierData(_root, signerAllocator, 0, siblingProof);
        vm.expectRevert(IMidnightAdapterPriceRatifierV1.InvalidProof.selector);
        adapter.isRatified(sibling, data, taker);
    }

    function testRatifyInvalidProof(uint256 seed) public {
        vm.setSeed(seed);
        Offer memory offer = _ratificationSetup();
        bytes32 wrongRoot = keccak256("wrong root");
        bytes32[] memory emptyProof = new bytes32[](0);
        bytes memory data = ratifierData(wrongRoot, signerAllocator, 0, emptyProof);
        vm.expectRevert(IMidnightAdapterPriceRatifierV1.InvalidProof.selector);
        adapter.isRatified(offer, data, taker);
    }

    function testRatifySetterNotAllocator(uint256 seed) public {
        vm.setSeed(seed);
        address otherSigner = makeAddr("nonAllocatorSigner");
        vm.assume(otherSigner != signerAllocator);
        assertFalse(parentVault.isAllocator(otherSigner), "must not be allocator");

        Offer memory offer = _ratificationSetup();
        bytes32 _root = HashLib.hashPriceRatifierV1Offer(offer, address(0));
        vm.prank(otherSigner);
        vm.expectRevert(IMidnightAdapterPriceRatifierV1.Unauthorized.selector);
        priceRatifier.setIsRootRatified(address(adapter), _root, true);
    }

    function testRatifySellOfferWithoutReduceOnly(uint256 seed) public {
        vm.setSeed(seed);
        Offer memory offer = _ratificationSetup();
        offer.buy = false;
        offer.reduceOnly = false;
        bytes32 _root = HashLib.hashPriceRatifierV1Offer(offer, address(0));
        bytes memory data = ratifierData(_root, signerAllocator);
        assertEq(adapter.isRatified(offer, data, taker), CALLBACK_SUCCESS, "callback success");
    }

    function testRatifyReduceOnlySellAccepted(uint256 seed) public {
        vm.setSeed(seed);
        Offer memory offer = _ratificationSetup();
        offer.buy = false;
        offer.reduceOnly = true;
        bytes32 _root = HashLib.hashPriceRatifierV1Offer(offer, address(0));
        bytes memory data = ratifierData(_root, signerAllocator);
        assertEq(adapter.isRatified(offer, data, taker), CALLBACK_SUCCESS, "callback success");
    }

    function testRatifyIncorrectReceiver(uint256 seed, address otherReceiver) public {
        vm.setSeed(seed);
        vm.assume(otherReceiver != address(adapter));
        Offer memory offer = _ratificationSetup();
        offer.buy = false;
        offer.reduceOnly = true;
        offer.receiverIfMakerIsSeller = otherReceiver;
        bytes32 _root = root(offer);
        bytes memory data = ratifierData(_root, signerAllocator);
        vm.expectRevert(IMidnightAdapterBase.IncorrectReceiver.selector);
        adapter.isRatified(offer, data, taker);
    }

    function testUnratifyRootByAllocator(uint256 seed) public {
        vm.setSeed(seed);
        Offer memory offer = _ratificationSetup();
        bytes32 _root = root(offer);
        bytes memory data = ratifierData(_root, signerAllocator);
        assertEq(adapter.isRatified(offer, data, taker), CALLBACK_SUCCESS, "ratifies before cancel");
        vm.expectEmit(address(priceRatifier));
        emit IMidnightAdapterPriceRatifierV1.SetIsRootRatified(signerAllocator, address(adapter), _root, false);
        vm.prank(signerAllocator);
        priceRatifier.setIsRootRatified(address(adapter), _root, false);
        assertFalse(priceRatifier.isRootRatified(address(adapter), _root), "root unratified");
        vm.expectRevert(IMidnightAdapterPriceRatifierV1.NotRatified.selector);
        adapter.isRatified(offer, data, taker);
    }

    function testUnratifyRootBySentinel(uint256 seed, address sentinel) public {
        vm.setSeed(seed);
        vm.assume(sentinel != signerAllocator);
        stdstore.target(address(parentVault)).sig("isSentinel(address)").with_key(sentinel).checked_write(true);
        Offer memory offer = _ratificationSetup();
        bytes32 _root = root(offer);
        bytes memory data = ratifierData(_root, signerAllocator);
        vm.prank(sentinel);
        priceRatifier.setIsRootRatified(address(adapter), _root, false);
        assertFalse(priceRatifier.isRootRatified(address(adapter), _root), "root unratified");
        vm.expectRevert(IMidnightAdapterPriceRatifierV1.NotRatified.selector);
        adapter.isRatified(offer, data, taker);
    }

    function testUnratifyRootUnauthorized(address caller) public {
        vm.assume(!parentVault.isAllocator(caller) && !parentVault.isSentinel(caller));
        vm.prank(caller);
        vm.expectRevert(IMidnightAdapterPriceRatifierV1.Unauthorized.selector);
        priceRatifier.setIsRootRatified(address(adapter), keccak256("some root"), false);
    }

    function testSetIsSubRatifierUnauthorized(address caller, address subRatifier, bool newIsSubRatifier) public {
        vm.assume(!parentVault.isAllocator(caller));
        vm.assume(newIsSubRatifier || !parentVault.isSentinel(caller));
        vm.prank(caller);
        vm.expectRevert(IMidnightAdapterBase.NotAuthorized.selector);
        adapter.setIsSubRatifier(subRatifier, newIsSubRatifier);
    }

    function testSentinelCannotAddSubRatifier(address sentinel, address subRatifier) public {
        vm.assume(!parentVault.isAllocator(sentinel));
        stdstore.target(address(parentVault)).sig("isSentinel(address)").with_key(sentinel).checked_write(true);
        vm.prank(sentinel);
        vm.expectRevert(IMidnightAdapterBase.NotAuthorized.selector);
        adapter.setIsSubRatifier(subRatifier, true);
    }

    function testAllocatorSetIsSubRatifier(address subRatifier) public {
        vm.expectEmit(address(adapter));
        emit IMidnightAdapterBase.SetIsSubRatifier(signerAllocator, subRatifier, true);
        vm.prank(signerAllocator);
        adapter.setIsSubRatifier(subRatifier, true);
        assertTrue(adapter.isSubRatifier(subRatifier), "authorized");
        vm.expectEmit(address(adapter));
        emit IMidnightAdapterBase.SetIsSubRatifier(signerAllocator, subRatifier, false);
        vm.prank(signerAllocator);
        adapter.setIsSubRatifier(subRatifier, false);
        assertFalse(adapter.isSubRatifier(subRatifier), "unauthorized");
    }

    function testSentinelCanRemoveSubRatifier(address sentinel) public {
        stdstore.target(address(parentVault)).sig("isSentinel(address)").with_key(sentinel).checked_write(true);
        vm.expectEmit(address(adapter));
        emit IMidnightAdapterBase.SetIsSubRatifier(sentinel, address(priceRatifier), false);
        vm.prank(sentinel);
        adapter.setIsSubRatifier(address(priceRatifier), false);
        assertFalse(adapter.isSubRatifier(address(priceRatifier)), "removed by sentinel");
    }

    function testRatifySubRatifierFailed(uint256 seed, address subRatifier) public {
        vm.setSeed(seed);
        vm.assume(!adapter.isSubRatifier(subRatifier));
        Offer memory offer = _ratificationSetup();
        vm.expectRevert(IMidnightAdapterBase.SubRatifierFailed.selector);
        adapter.isRatified(offer, abi.encode(subRatifier, bytes("")), taker);
    }

    function testRogueSubRatifierCannotBypassShapeChecks() public {
        address attacker = makeAddr("attacker");
        addSubRatifier(adapter, address(this));
        bytes memory rogueData = abi.encode(address(this), bytes(""));

        Offer memory bought = buy(30 days, 1e18);
        Offer memory offer = makeSellOffer(bought.market, 0, MAX_TICK);
        offer.maxUnits =
            uint128(TakeAmountsLib.sellerAssetsToUnits(address(midnight), _marketId(bought.market), offer, 0.5e18));

        offer.receiverIfMakerIsSeller = attacker;
        vm.prank(taker);
        vm.expectRevert(IMidnightAdapterBase.IncorrectReceiver.selector);
        midnight.take(offer, rogueData, offer.maxUnits, taker, address(0), address(0), "");
        offer.receiverIfMakerIsSeller = address(adapter);

        offer.callback = address(0);
        vm.prank(taker);
        vm.expectRevert(IMidnightAdapterBase.IncorrectCallbackAddress.selector);
        midnight.take(offer, rogueData, offer.maxUnits, taker, address(0), address(0), "");
        offer.callback = address(adapter);

        offer.reduceOnly = false;

        // The rogue sub-ratifier does approve the same offer once well-shaped.
        vm.prank(taker);
        midnight.take(offer, rogueData, offer.maxUnits, taker, address(0), address(0), "");
    }

    function testDisableSubRatifierBlocksTake() public {
        Offer memory offer = makeBuyOffer(30 days, 1e18, discountTick);
        midnight.supplyCollateral(offer.market, 0, offer.maxUnits, taker);
        midnight.supplyCollateral(offer.market, 1, offer.maxUnits, taker);
        bytes memory data = ratify([offer], signerAllocator);

        vm.prank(signerAllocator);
        adapter.setIsSubRatifier(address(priceRatifier), false);
        vm.prank(taker);
        vm.expectRevert(IMidnightAdapterBase.SubRatifierFailed.selector);
        midnight.take(offer, data, offer.maxUnits, taker, taker, address(0), "");

        addSubRatifier(adapter, address(priceRatifier));
        vm.prank(taker);
        midnight.take(offer, data, offer.maxUnits, taker, taker, address(0), "");
        assertGt(adapter.realAssets(), 0, "position opened");
    }

    function testRemovedAllocatorCannotRatify() public {
        Offer memory offer = makeBuyOffer(30 days, 1e18, discountTick);
        bytes32 _root = root(offer);
        stdstore.target(address(parentVault)).sig("isAllocator(address)").with_key(signerAllocator).checked_write(false);
        vm.prank(signerAllocator);
        vm.expectRevert(IMidnightAdapterPriceRatifierV1.Unauthorized.selector);
        priceRatifier.setIsRootRatified(address(adapter), _root, true);
    }

    function testSharedRatifierTwoAdapters() public {
        address otherAllocator = makeAddr("otherAllocator");
        VaultV2Mock otherVault = new VaultV2Mock(address(loanToken), owner, curator, otherAllocator, address(0));
        IMidnightAdapter otherAdapter = IMidnightAdapter(factory.createMidnightAdapter(address(otherVault)));
        vm.prank(curator);
        otherAdapter.submit(abi.encodeCall(IMidnightAdapterBase.setMaxTtm, (type(uint32).max)));
        otherAdapter.setMaxTtm(type(uint32).max);
        vm.prank(otherAllocator);
        otherAdapter.setIsSubRatifier(address(priceRatifier), true);
        disableDurationCaps(otherAdapter);
        deal(address(loanToken), address(otherVault), 1_000_000e18);

        Offer memory offerA = makeBuyOffer(30 days, 1e18, discountTick);
        Offer memory offerB = makeBuyOffer(30 days, 1e18, discountTick);
        offerB.maker = address(otherAdapter);
        offerB.callback = address(otherAdapter);
        offerB.ratifier = address(otherAdapter);
        midnight.supplyCollateral(offerA.market, 0, 2 * uint256(offerA.maxUnits), taker);
        midnight.supplyCollateral(offerA.market, 1, 2 * uint256(offerA.maxUnits), taker);

        // A's allocator cannot act on B's roots.
        vm.prank(signerAllocator);
        vm.expectRevert(IMidnightAdapterPriceRatifierV1.Unauthorized.selector);
        priceRatifier.setIsRootRatified(address(otherAdapter), root(offerB), false);

        // Canceling A's root value on B does not affect A.
        vm.prank(otherAllocator);
        priceRatifier.setIsRootRatified(address(otherAdapter), root(offerA), false);
        bytes memory dataA = ratify([offerA], signerAllocator);
        vm.prank(taker);
        midnight.take(offerA, dataA, offerA.maxUnits, taker, taker, address(0), "");
        assertGt(adapter.realAssets(), 0, "A position opened");

        // B takes with its own allocator through the same ratifier deployment.
        vm.prank(otherAllocator);
        priceRatifier.setIsRootRatified(address(otherAdapter), root(offerB), true);
        bytes memory dataB =
            abi.encode(address(priceRatifier), abi.encode(root(offerB), 0, proof([offerB]), address(0)));
        vm.prank(taker);
        midnight.take(offerB, dataB, offerB.maxUnits, taker, taker, address(0), "");
        assertGt(otherAdapter.realAssets(), 0, "B position opened");
    }

    function testGarbageSubRatifierRatifierFailed() public {
        GarbageSubRatifier garbage = new GarbageSubRatifier();
        addSubRatifier(adapter, address(garbage));
        Offer memory offer = makeBuyOffer(30 days, 1e18, discountTick);
        midnight.supplyCollateral(offer.market, 0, offer.maxUnits, taker);
        midnight.supplyCollateral(offer.market, 1, offer.maxUnits, taker);
        bytes memory data = abi.encode(address(garbage), bytes(""));
        assertEq(adapter.isRatified(offer, data, taker), bytes32(uint256(1)), "return value forwarded");
        vm.prank(taker);
        vm.expectRevert(IMidnight.RatifierFailed.selector);
        midnight.take(offer, data, offer.maxUnits, taker, taker, address(0), "");
    }

    /* MAX TTM */

    function testSetMaxTtmNotAuthorized(address caller, uint256 newMaxTtm) public {
        vm.assume(caller != curator);
        vm.expectRevert(IMidnightAdapterBase.NotAuthorized.selector);
        vm.prank(caller);
        adapter.submit(abi.encodeCall(IMidnightAdapterBase.setMaxTtm, (newMaxTtm)));
    }

    function testSetMaxTtmNotTimelocked(address caller, uint256 newMaxTtm) public {
        vm.expectRevert(IMidnightAdapterBase.DataNotTimelocked.selector);
        vm.prank(caller);
        adapter.setMaxTtm(newMaxTtm);
    }

    function testSetMaxTtmAuthorized(uint256 oldMaxTtm, uint256 newMaxTtm) public {
        oldMaxTtm = bound(oldMaxTtm, 0, type(uint32).max);
        newMaxTtm = bound(newMaxTtm, 0, type(uint32).max);
        setUpMaxTtm(oldMaxTtm);
        vm.prank(curator);
        adapter.submit(abi.encodeCall(IMidnightAdapterBase.setMaxTtm, (newMaxTtm)));
        vm.expectEmit(address(adapter));
        emit IMidnightAdapterBase.SetMaxTtm(newMaxTtm);
        adapter.setMaxTtm(newMaxTtm);
        assertEq(adapter.maxTtm(), newMaxTtm, "maxTtm");
    }

    function testSetMaxTtmOverflow(uint256 newMaxTtm) public {
        newMaxTtm = bound(newMaxTtm, uint256(type(uint32).max) + 1, type(uint256).max);
        vm.prank(curator);
        adapter.submit(abi.encodeCall(IMidnightAdapterBase.setMaxTtm, (newMaxTtm)));
        vm.expectRevert(ErrorsLib.CastOverflow.selector);
        adapter.setMaxTtm(newMaxTtm);
    }

    function testSetMaxTtmTimelocked(uint256 newMaxTtm, uint256 duration) public {
        newMaxTtm = bound(newMaxTtm, 0, type(uint32).max);
        duration = bound(duration, 1, 3650 days);
        submitTimelock(IMidnightAdapterBase.setMaxTtm.selector, duration);

        bytes memory data = abi.encodeCall(IMidnightAdapterBase.setMaxTtm, (newMaxTtm));
        vm.prank(curator);
        adapter.submit(data);

        skip(duration - 1);
        vm.expectRevert(IMidnightAdapterBase.TimelockNotExpired.selector);
        adapter.setMaxTtm(newMaxTtm);

        skip(1);
        vm.expectEmit(address(adapter));
        emit IMidnightAdapterBase.Accept(IMidnightAdapterBase.setMaxTtm.selector, data);
        vm.expectEmit(address(adapter));
        emit IMidnightAdapterBase.SetMaxTtm(newMaxTtm);
        adapter.setMaxTtm(newMaxTtm);
        assertEq(adapter.maxTtm(), newMaxTtm, "maxTtm");
        assertEq(adapter.executableAt(data), 0, "executableAt");

        vm.expectRevert(IMidnightAdapterBase.DataNotTimelocked.selector);
        adapter.setMaxTtm(newMaxTtm);
    }

    function testMaxTtmUpdatesApplyToSignedOffer() public {
        Offer memory offer = makeBuyOffer(30 days, 1e18, MAX_TICK);
        midnight.supplyCollateral(offer.market, 0, offer.maxUnits, taker);
        bytes memory data = ratify([offer], signerAllocator);
        setUpMaxTtm(30 days - 1);

        vm.expectRevert(IMidnightAdapterBase.BuyTtmTooHigh.selector);
        this.takeWithAccrual(offer, data, taker, address(0));
        assertEq(midnight.consumed(address(adapter), offer.group), 0, "offer not consumed");

        setUpMaxTtm(30 days);
        this.takeWithAccrual(offer, data, taker, address(0));
        assertEq(adapter.marketData(_marketId(offer.market)).netCredit, offer.maxUnits, "increased maxTtm accepted");
    }

    function testMaxTtmBoundary(uint256 maxTtm, bool takerBuy) public {
        maxTtm = bound(maxTtm, 0, 365 days);
        setUpMaxTtm(maxTtm);
        Offer memory offer = makeBuyOffer(maxTtm + 1, 1e18, MAX_TICK);
        if (takerBuy) {
            offer = makeExternalOffer(offer.market, false, 1e18, MAX_TICK);
        } else {
            midnight.supplyCollateral(offer.market, 0, offer.maxUnits, taker);
        }
        offer.expiry = offer.market.maturity;
        uint256 balanceBefore = loanToken.balanceOf(address(parentVault));

        if (takerBuy) {
            vm.prank(signerAllocator);
            vm.expectRevert(IMidnightAdapterBase.BuyTtmTooHigh.selector);
            adapter.take(offer, "", offer.maxUnits);
        } else {
            vm.expectRevert(IMidnightAdapterBase.BuyTtmTooHigh.selector);
            take(offer);
        }
        assertEq(adapter.marketIdsLength(), 0, "failed buy leaves no markets");
        assertEq(parentVault.allocation(adapter.adapterId()), 0, "failed buy leaves no allocation");
        assertEq(loanToken.balanceOf(address(parentVault)), balanceBefore, "failed buy leaves funds unchanged");
        assertEq(midnight.consumed(offer.maker, offer.group), 0, "offer not consumed");

        skip(1);
        if (takerBuy) {
            vm.prank(signerAllocator);
            adapter.take(offer, "", offer.maxUnits);
        } else {
            take(offer);
        }
        assertEq(adapter.marketData(_marketId(offer.market)).netCredit, offer.maxUnits, "remaining duration accepted");
        assertEq(parentVault.allocation(adapter.adapterId()), offer.maxUnits, "allocation");
        assertEq(loanToken.balanceOf(address(parentVault)), balanceBefore - 1e18, "paid assets");
    }

    function testMaxTtmBelowLimit(uint256 maxTtm, uint256 duration) public {
        maxTtm = bound(maxTtm, 1, 365 days);
        duration = bound(duration, 0, maxTtm - 1);
        setUpMaxTtm(maxTtm);

        Offer memory offer = buy(duration, 1e18);

        assertEq(adapter.marketData(_marketId(offer.market)).netCredit, offer.maxUnits, "shorter duration accepted");
    }

    function testMaxTtmCoversMidnightMaturityLimitAfter2106() public {
        vm.warp(uint256(type(uint32).max) + 1);
        Offer memory offer = buy(100 * 365 days, 1e18);

        MarketData memory data = adapter.marketData(_marketId(offer.market));
        assertEq(data.netCredit, offer.maxUnits);
        assertEq(data.maturity, vm.getBlockTimestamp() + 100 * 365 days);
        assertEq(adapter.maxTtm(), type(uint32).max);
        assertEq(adapter.shortfallUpdatedAt(), vm.getBlockTimestamp());
    }

    function testMaxTtmZero() public {
        setUpMaxTtm(0);
        Offer memory offer = makeBuyOffer(1, 1e18, MAX_TICK);
        midnight.supplyCollateral(offer.market, 0, offer.maxUnits, taker);
        vm.expectRevert(IMidnightAdapterBase.BuyTtmTooHigh.selector);
        take(offer);

        offer = buy(0, 1e18);
        assertEq(adapter.marketData(_marketId(offer.market)).netCredit, offer.maxUnits, "at-maturity buy accepted");
    }

    function testMaxTtmDoesNotRestrictSells(uint256 maxTtm, bool takerSale) public {
        maxTtm = bound(maxTtm, 1, 365 days);
        setUpMaxTtm(maxTtm);
        Offer memory offer = buy(maxTtm, 1e18);
        setUpMaxTtm(0);
        if (takerSale) {
            Offer memory buyOffer = makeExternalOffer(offer.market, true, 1e18, MAX_TICK);
            vm.prank(signerAllocator);
            adapter.take(buyOffer, "", buyOffer.maxUnits);
        } else {
            sell(offer.market, offer.maxUnits);
        }

        assertEq(adapter.marketData(_marketId(offer.market)).netCredit, 0, "sell accepted");
        assertEq(parentVault.allocation(adapter.adapterId()), 0, "allocation cleared");
    }

    /* FACTORY */

    function testFactoryCreateMidnightAdapter() public {
        VaultV2Mock newVault = new VaultV2Mock(address(loanToken), owner, curator, signerAllocator, address(0));

        vm.expectEmit(true, false, false, false, address(factory));
        emit IMidnightAdapterFactory.CreateMidnightAdapter(address(newVault), address(0));
        address newAdapter = factory.createMidnightAdapter(address(newVault));

        assertEq(factory.midnightAdapter(address(newVault)), newAdapter, "midnightAdapter");
        assertTrue(factory.isMidnightAdapter(newAdapter), "isMidnightAdapter");
        assertEq(IMidnightAdapter(newAdapter).parentVault(), address(newVault), "parentVault");
        assertEq(IMidnightAdapter(newAdapter).midnight(), address(midnight), "midnight");
        assertEq(IMidnightAdapter(newAdapter).durations(), allDurations, "durations");
        assertEq(IMidnightAdapter(newAdapter).maxTtm(), 0, "default maxTtm");
        assertTrue(midnight.isAuthorized(newAdapter, newAdapter), "adapter is its own ratifier");

        // Fixed salt: one adapter per vault.
        vm.expectRevert();
        factory.createMidnightAdapter(address(newVault));
    }

    function testFactoryConstructor() public {
        vm.expectEmit();
        emit IMidnightAdapterFactory.CreateMidnightAdapterFactory(address(midnight), allDurations);
        MidnightAdapterFactory newFactory = new MidnightAdapterFactory(address(midnight), allDurations);
        assertEq(newFactory.midnight(), address(midnight), "midnight");
        assertEq(newFactory.durationsLength(), allDurations.length, "durationsLength");
    }

    /* DURATIONS */

    function testConstructorGetters() public view {
        assertEq(adapter.asset(), address(loanToken), "asset");
        assertEq(adapter.parentVault(), address(parentVault), "parentVault");
        assertEq(adapter.midnight(), address(midnight), "midnight");
        assertEq(adapter.maxTtm(), type(uint32).max, "maxTtm");
        assertEq(adapter.skimRecipient(), address(0), "skimRecipient");
        assertEq(adapter.durationsLength(), allDurations.length, "durationsLength");
        bytes32 expectedPackedDurations;
        for (uint256 i = 0; i < allDurations.length; i++) {
            expectedPackedDurations |= bytes32(allDurations[i] << (32 * i));
        }
        assertEq(adapter.packedDurations(), expectedPackedDurations, "packedDurations");
    }

    /* INTERNAL DURATION CAPS */

    function testDurationCapsDefaultToZero() public {
        VaultV2Mock vault = new VaultV2Mock(address(loanToken), owner, curator, signerAllocator, address(0));
        IMidnightAdapter fresh = IMidnightAdapter(factory.createMidnightAdapter(address(vault)));
        for (uint256 i; i < allDurations.length; i++) {
            assertEq(vault.relativeCap(keccak256(durationIdData(fresh, allDurations[i]))), 0);
            assertEq(vault.absoluteCap(keccak256(durationIdData(fresh, allDurations[i]))), 0);
        }
        assertEq(storedDurationAllocations(fresh), new uint256[](allDurations.length));
    }

    /// forge-config: default.isolate = true
    function testDurationCapsUseVaultGovernance() public {
        setUpRealVault();
        bytes memory idData = durationIdData(adapter, 7 days);
        bytes32 id = keccak256(idData);
        decreaseDurationCap(1, 0);
        Offer memory blocked = fundedDurationOffer(7 days, 1e18);
        vm.expectRevert(IMidnightAdapterBase.DurationRelativeCapExceeded.selector);
        take(blocked);

        vm.expectRevert(ErrorsLib.Unauthorized.selector);
        realVault.decreaseRelativeCap(idData, 0);
        submitAndCall(
            realVault, abi.encodeCall(IVaultV2.increaseTimelock, (IVaultV2.increaseRelativeCap.selector, 1 days))
        );
        bytes memory data = abi.encodeCall(IVaultV2.increaseRelativeCap, (idData, 0.1e18));
        vm.expectRevert(ErrorsLib.DataNotTimelocked.selector);
        realVault.increaseRelativeCap(idData, 0.1e18);
        vm.prank(curator);
        realVault.submit(data);
        vm.expectRevert(ErrorsLib.TimelockNotExpired.selector);
        realVault.increaseRelativeCap(idData, 0.1e18);
        skip(1 days);
        realVault.increaseRelativeCap(idData, 0.1e18);
        assertEq(realVault.relativeCap(id), 0.1e18);
        buyOnRealVault(7 days, 1e18);
        assertEq(storedDurationAllocations(adapter)[1], 1e18);
        assertEq(realVault.allocation(id), 0, "duration exposure is internal to the adapter");
        assertEq(realVault.absoluteCap(id), type(uint128).max, "duration absolute cap disabled");

        address sentinel = makeAddr("duration sentinel");
        vm.prank(owner);
        realVault.setIsSentinel(sentinel, true);
        vm.prank(sentinel);
        realVault.decreaseRelativeCap(idData, 0);
        assertEq(realVault.relativeCap(id), 0);
        blocked = fundedDurationOffer(8 days, 1e18);
        vm.expectRevert(IMidnightAdapterBase.DurationRelativeCapExceeded.selector);
        take(blocked);
    }

    /// forge-config: default.isolate = true
    function testDurationAbsoluteCapExceeded() public {
        setUpRealVault();
        decreaseDurationAbsoluteCap(1, 1e18);

        Offer memory overCap = fundedDurationOffer(7 days, 1.1e18);
        vm.expectRevert(IMidnightAdapterBase.DurationAbsoluteCapExceeded.selector);
        take(overCap);

        take(fundedDurationOffer(7 days, 1e18));
        take(fundedDurationOffer(6 days, 2e18));
        assertEq(storedDurationAllocations(adapter)[1], 1e18, "7 day absolute cap");
    }

    /// forge-config: default.isolate = true
    function testDurationAbsoluteCapZeroDoesNotBlockShorterBuys() public {
        setUpRealVault();
        uint256 longestDurationIndex = allDurations.length - 1;
        decreaseDurationAbsoluteCap(longestDurationIndex, 0);

        buyOnRealVault(allDurations[longestDurationIndex - 1], 1e18);
        assertEq(storedDurationAllocations(adapter)[longestDurationIndex], 0, "longest duration");
    }

    /// forge-config: default.isolate = true
    function testDurationCapsOnlyCheckAffectedDurations() public {
        setUpRealVault();
        buyOnRealVault(90 days, 2e18);
        decreaseDurationCap(2, 0.1e18);

        take(fundedDurationOffer(7 days, 1e18));
        assertEq(storedDurationAllocations(adapter)[2], 2e18, "long duration remains over cap");

        Offer memory overCap = fundedDurationOffer(30 days, 1e18);
        vm.expectRevert(IMidnightAdapterBase.DurationRelativeCapExceeded.selector);
        take(overCap);
    }

    /// forge-config: default.isolate = true
    function testDurationCapsAllowBuyBelowSmallestDuration() public {
        setUpRealVault();
        for (uint256 i; i < allDurations.length; i++) {
            decreaseDurationCap(i, 0);
            decreaseDurationAbsoluteCap(i, 0);
        }

        buyOnRealVault(allDurations[0] - 1, 1e18);
        assertEq(storedDurationAllocations(adapter), new uint256[](allDurations.length));
    }

    /// forge-config: default.isolate = true
    function testDurationCapsUseScopedVaultIds() public {
        setUpRealVault();
        decreaseDurationCap(1, 0);
        bytes memory idData = durationIdData(adapter, 7 days);
        submitAndCall(
            realVault, abi.encodeCall(IVaultV2.increaseRelativeCap, (abi.encode("duration", uint256(7 days)), 1e18))
        );
        submitAndCall(
            realVault,
            abi.encodeCall(
                IVaultV2.increaseRelativeCap, (abi.encode("duration", makeAddr("other adapter"), uint256(7 days)), 1e18)
            )
        );
        Offer memory offer = fundedDurationOffer(7 days, 1e18);
        vm.expectRevert(IMidnightAdapterBase.DurationRelativeCapExceeded.selector);
        take(offer);

        submitAndCall(realVault, abi.encodeCall(IVaultV2.increaseRelativeCap, (idData, 0.1e18)));
        take(offer);
        assertEq(storedDurationAllocations(adapter)[1], 1e18);
        assertEq(realVault.allocation(keccak256(idData)), 0);
        bytes32[] memory ids = adapter.ids(offer.market);
        for (uint256 i; i < ids.length; i++) {
            assertNotEq(ids[i], keccak256(idData));
        }
    }

    /// forge-config: default.isolate = true
    function testDurationCapsMultipleHorizonsAndMakerBuy() public {
        setUpRealVault();
        decreaseDurationCap(2, 0.5e18); // At most 50% at or beyond 30 days.
        decreaseDurationCap(3, 0.2e18); // At most 20% at or beyond 90 days.
        buyOnRealVault(90 days, 2e18);
        buyOnRealVault(30 days, 3e18);
        uint256[] memory allocations = storedDurationAllocations(adapter);
        assertEq(allocations[2], 5e18);
        assertEq(allocations[3], 2e18);

        Offer memory tooLong = fundedDurationOffer(91 days, 2);
        vm.expectRevert(IMidnightAdapterBase.DurationRelativeCapExceeded.selector);
        take(tooLong);
        Offer memory tooMuch = fundedDurationOffer(31 days, 2);
        vm.expectRevert(IMidnightAdapterBase.DurationRelativeCapExceeded.selector);
        take(tooMuch);
        assertEq(storedDurationAllocations(adapter), allocations, "failed buys roll back");
        buyOnRealVault(29 days, 1e18);
        assertEq(storedDurationAllocations(adapter)[2], 5e18, "short purchase does not consume long caps");
    }

    /// forge-config: default.isolate = true
    function testDurationCapsTakerBuyAndBoundary() public {
        setUpRealVault();
        decreaseDurationCap(1, 0);
        Market memory market = makeBuyOffer(7 days, 1e18, MAX_TICK).market;
        Offer memory offer = makeExternalOffer(market, false, 1e18, MAX_TICK);
        vm.prank(signerAllocator);
        vm.expectRevert(IMidnightAdapterBase.DurationRelativeCapExceeded.selector);
        adapter.take(offer, "", offer.maxUnits);
        assertEq(adapter.marketIdsLength(), 0);

        // Exactly seven days was included; one second below it is excluded.
        skip(1);
        offer.expiry = block.timestamp;
        vm.prank(signerAllocator);
        adapter.take(offer, "", offer.maxUnits);
        assertEq(storedDurationAllocations(adapter)[1], 0);
        assertEq(storedDurationAllocations(adapter)[0], 1e18);
    }

    /// forge-config: default.isolate = true
    function testDurationCapsUseNetCreditNotPurchasePrice() public {
        setUpRealVault();
        decreaseDurationCap(2, 0.1e18);
        Offer memory offer = makeBuyOffer(30 days, 1e18, discountTick);
        offer.maker = address(adapter);
        offer.ratifier = address(adapter);
        midnight.supplyCollateral(offer.market, 0, offer.maxUnits, taker);
        assertGt(offer.maxUnits, 1e18);
        vm.expectRevert(IMidnightAdapterBase.DurationRelativeCapExceeded.selector);
        take(offer);
        assertEq(adapter.marketIdsLength(), 0);
    }

    /// forge-config: default.isolate = true
    function testDurationCapsReleaseCapacityWithTime() public {
        setUpRealVault();
        decreaseDurationCap(1, 0.1e18);
        buyOnRealVault(7 days, 1e18);
        Offer memory next = fundedDurationOffer(8 days, 1e18);
        vm.expectRevert(IMidnightAdapterBase.DurationRelativeCapExceeded.selector);
        take(next);
        skip(1);
        next.expiry = block.timestamp;
        take(next);
        assertEq(storedDurationAllocations(adapter)[1], 1e18);
        assertEq(storedDurationAllocations(adapter)[0], 2e18);
    }

    /// forge-config: default.isolate = true
    function testDurationCapsKeepLossesUntilSynchronized(bool sameMarket) public {
        setUpRealVault();
        Offer memory initial = buyOnRealVault(30 days, 2e18);
        decreaseDurationCap(2, 0.25e18);
        this.realizeDefault(initial.market, ORACLE_PRICE_SCALE / 2);
        assertEq(adapter.marketData(_marketId(initial.market)).netCredit, 2e18, "stored credit remains stale");
        assertEq(storedDurationAllocations(adapter)[2], 2e18, "loss remains counted");
        OracleMock(storedCollaterals[0].oracle).setPrice(ORACLE_PRICE_SCALE);
        OracleMock(storedCollaterals[1].oracle).setPrice(ORACLE_PRICE_SCALE);
        Offer memory next = fundedDurationOffer(sameMarket ? 30 days : 31 days, 1e18);
        next.group = bytes32("purchase after duration loss");
        if (!sameMarket) {
            vm.expectRevert(IMidnightAdapterBase.DurationRelativeCapExceeded.selector);
            take(next);
            midnight.updatePosition(initial.market, address(adapter));
            assertEq(storedDurationAllocations(adapter)[2], 2e18, "Midnight update alone does not synchronize caps");
            adapter.withdrawToVault(initial.market, 0);
            assertApproxEqAbs(storedDurationAllocations(adapter)[2], 1e18, 1, "zero withdrawal synchronizes loss");
        }
        take(next);
        assertApproxEqAbs(storedDurationAllocations(adapter)[2], 2e18, 1);
    }

    /// forge-config: default.isolate = true
    function testDurationAllocationsConservativeAfterLoss(uint256 fee, uint256 elapsed, uint256 price) public {
        midnight.setDefaultContinuousFee(address(loanToken), bound(fee, 0, MAX_CONTINUOUS_FEE));
        Offer memory initial = freshPosition(discountTick);
        uint256 storedCredit = adapter.marketData(_marketId(initial.market)).netCredit;
        skip(bound(elapsed, 0, 6 days));
        this.realizeDefault(initial.market, bound(price, 0, ORACLE_PRICE_SCALE / 2));
        (uint128 credit, uint128 pendingFee,) = midnight.updatePosition(initial.market, address(adapter));
        uint256 liveCredit = credit - pendingFee;
        assertEq(storedDurationAllocations(adapter)[0], storedCredit, "fees and losses do not change stored caps");
        assertGe(storedCredit, liveCredit, "stored credit conservatively bounds live credit");
        adapter.withdrawToVault(initial.market, 0);
        assertEq(storedDurationAllocations(adapter)[0], liveCredit, "synchronized exposure");
    }

    /// forge-config: default.isolate = true
    function testDurationCapsDoNotBlockExits(uint256 exitKind) public {
        exitKind = bound(exitKind, 0, 2);
        setUpRealVault();
        Offer memory initial = buyOnRealVault(7 days, 2e18);
        decreaseDurationCap(1, 0);
        if (exitKind == 0) {
            sellUnits(initial.market, 1e18, MAX_TICK);
        } else if (exitKind == 1) {
            vm.prank(taker);
            midnight.repay(initial.market, 1e18, taker, address(0), "");
            adapter.withdrawToVault(initial.market, 1e18);
        } else {
            forceDeallocateOnRealVault(initial.market, 1e18);
        }
        assertEq(storedDurationAllocations(adapter)[1], 1e18);
        assertEq(realVault.allocation(adapter.adapterId()), 1e18);
    }

    /// forge-config: default.isolate = true
    function testDurationCapsCheckAfterSelfFunding() public {
        Offer memory initial = freshPosition(MAX_TICK);
        decreaseDurationCap(1, 0.8e18);
        vm.prank(taker);
        midnight.repay(initial.market, 2e18, taker, address(0), "");
        Offer memory next = fundedDurationOffer(7 days, 4e18);
        next.group = bytes32("funded duration buy");
        next.callbackData = abi.encode(address(adapter), abi.encode(initial.market));
        // The seven-day exposure falls from 12 to 10 during funding: still above 80%.
        vm.expectRevert(IMidnightAdapterBase.DurationRelativeCapExceeded.selector);
        take(next);
        assertEq(storedDurationAllocations(adapter)[1], 8e18);

        // A six-day buy must be evaluated after removing the two units used to fund it.
        decreaseDurationCap(1, 0.6e18);
        next = fundedDurationOffer(6 days, 4e18);
        next.callbackData = abi.encode(address(adapter), abi.encode(initial.market));
        take(next);
        assertEq(storedDurationAllocations(adapter)[1], 6e18);
        assertEq(storedDurationAllocations(adapter)[0], 10e18);
    }

    /// forge-config: default.isolate = true
    function testDurationCapsUseFirstTotalAssets() public {
        setUpRealVault();
        decreaseDurationCap(1, 0.1e18);
        Offer memory offer = fundedDurationOffer(7 days, 2e18);
        deal(address(loanToken), address(this), 10e18);
        vm.expectRevert(IMidnightAdapterBase.DurationRelativeCapExceeded.selector);
        this.depositThenDurationBuy(offer);
        assertEq(adapter.marketIdsLength(), 0);
        // A deposit settled in an earlier transaction does expand the cap.
        realVault.deposit(10e18, address(this));
        take(offer);
        assertEq(storedDurationAllocations(adapter)[1], 2e18);
    }

    function depositThenDurationBuy(Offer memory offer) external {
        realVault.accrueInterest();
        realVault.deposit(10e18, address(this));
        directTake(offer);
    }

    /// forge-config: default.isolate = true
    function testDurationCapsKeepUnsettledSalesCounted(bool longBuy) public {
        Offer memory initial = freshPosition(MAX_TICK);
        decreaseDurationCap(1, 0.8e18);
        EagerLossCallback callback = newCallback();
        Offer memory inner = fundedDurationOffer(longBuy ? 8 days : 6 days, 1e18);
        midnight.supplyCollateral(inner.market, 0, 2e18, address(callback));
        callback.push(address(this), abi.encodeCall(this.assertDurationAllocation, (1, 8e18)), bytes4(0));
        callback.push(
            address(midnight),
            abi.encodeCall(
                IMidnight.take,
                (
                    inner,
                    ratify([inner], signerAllocator),
                    inner.maxUnits,
                    address(callback),
                    address(callback),
                    address(0),
                    ""
                )
            ),
            longBuy ? IMidnightAdapterBase.DurationRelativeCapExceeded.selector : bytes4(0)
        );
        this.accruedCallbackSale(makeSellOffer(initial.market, 4e18, MAX_TICK), callback);
        assertEq(storedDurationAllocations(adapter)[1], 4e18);
        assertEq(adapter.marketData(_marketId(inner.market)).netCredit, longBuy ? 0 : 1e18);
    }

    function assertDurationAllocation(uint256 durationIndex, uint256 expected) external view {
        assertEq(storedDurationAllocations(adapter)[durationIndex], expected);
    }

    /// forge-config: default.isolate = true
    function testDurationCapAmountBoundary(uint256 cap) public {
        cap = bound(cap, 1, 0.4e18);
        setUpRealVault();
        decreaseDurationCap(2, cap);
        uint256 limit = uint256(10e18).mulDivDown(cap, 1e18);
        buyOnRealVault(30 days, limit);
        Offer memory extra = fundedDurationOffer(31 days, 2);
        vm.expectRevert(IMidnightAdapterBase.DurationRelativeCapExceeded.selector);
        take(extra);
        assertEq(storedDurationAllocations(adapter)[2], limit);
    }

    function testDurationCapsAtMarketLimit() public {
        for (uint256 i; i < 250; i++) {
            buy(180 days + i, 1e18);
        }
        stdstore.target(address(parentVault)).sig("firstTotalAssets()").checked_write(1000e18);
        for (uint256 i; i < allDurations.length; i++) {
            decreaseDurationCap(i, 0.5e18);
        }
        uint256[] memory allocations = storedDurationAllocations(adapter);
        for (uint256 i; i < allocations.length; i++) {
            assertEq(allocations[i], 250e18);
        }

        Offer memory extra = makeBuyOffer(180 days, 1e18, MAX_TICK);
        extra.group = bytes32("buy at market limit");
        take(extra);
        assertEq(storedDurationAllocations(adapter)[4], 251e18);
        assertEq(adapter.marketIdsLength(), 250);
    }

    function testDurationAllocationsLengthTooHigh() public {
        uint256 length = adapter.durationsLength() + 1;
        vm.expectRevert(IMidnightAdapterBase.InvalidLength.selector);
        adapter.durationAllocations(length);
    }

    /// @dev Returns stored exposure across all configured durations.
    function storedDurationAllocations(IMidnightAdapter target) internal view returns (uint256[] memory allocations) {
        return target.durationAllocations(target.durationsLength());
    }

    function fundedDurationOffer(uint256 duration, uint256 assets) internal returns (Offer memory offer) {
        offer = makeBuyOffer(duration, assets, MAX_TICK);
        offer.maker = address(adapter);
        offer.ratifier = address(adapter);
        midnight.supplyCollateral(offer.market, 0, assets, taker);
    }

    /* IDS */

    function testIds(
        uint256 collateralCount,
        uint256 maturity,
        address enterGate,
        address liquidatorGate,
        uint256 rcfThreshold
    ) public view {
        collateralCount = bound(collateralCount, 0, 5);

        Market memory market;

        CollateralParams[] memory collateralParams = new CollateralParams[](collateralCount);
        for (uint256 i = 0; i < collateralCount; i++) {
            collateralParams[i].token = address(uint160(i));
            collateralParams[i].lltv = i + 1;
            collateralParams[i].liquidationCursor = i + 2;
            collateralParams[i].oracle = address(uint160(i + 3));
        }
        market.collateralParams = collateralParams;
        market.maturity = bound(maturity, 1, 700 days);
        market.enterGate = enterGate;
        market.liquidatorGate = liquidatorGate;
        market.rcfThreshold = rcfThreshold;

        bytes32[] memory ids = adapter.ids(market);
        assertEq(ids[0], adapter.adapterId());
        assertEq(ids[1], keccak256(abi.encode("enterGate", enterGate)));
        assertEq(ids[2], keccak256(abi.encode("liquidatorGate", liquidatorGate)));
        assertEq(ids[3], keccak256(abi.encode("rcfThreshold", rcfThreshold)));
        for (uint256 i = 0; i < market.collateralParams.length; i++) {
            assertEq(ids[i * 2 + 4], keccak256(abi.encode("collateralToken", market.collateralParams[i].token)));
            assertEq(
                ids[i * 2 + 5],
                keccak256(
                    abi.encode(
                        "collateralParams",
                        market.collateralParams[i].token,
                        market.collateralParams[i].lltv,
                        market.collateralParams[i].liquidationCursor,
                        market.collateralParams[i].oracle
                    )
                )
            );
        }

        assertEq(ids.length, 4 + market.collateralParams.length * 2);
    }

    /* ALLOCATION UPDATES */

    function testMarketConfigCaps(uint256 configField) public {
        configField = bound(configField, 0, 2);
        setUpRealVault();
        address gate = makeAddr("marketGate");
        vm.etch(gate, hex"01");
        vm.mockCall(gate, bytes(""), abi.encode(true));

        Offer memory offer = makeBuyOffer(7 days, 1e18, MAX_TICK);
        offer.maker = address(adapter);
        offer.ratifier = address(adapter);
        if (configField == 0) offer.market.enterGate = gate;
        else if (configField == 1) offer.market.liquidatorGate = gate;
        else offer.market.rcfThreshold = 1e18;
        midnight.supplyCollateral(offer.market, 0, 0.5e18, taker);
        midnight.supplyCollateral(offer.market, 1, 0.5e18, taker);

        bytes memory idData;
        if (configField == 0) idData = abi.encode("enterGate", offer.market.enterGate);
        else if (configField == 1) idData = abi.encode("liquidatorGate", offer.market.liquidatorGate);
        else idData = abi.encode("rcfThreshold", offer.market.rcfThreshold);
        bytes memory data = ratify([offer], signerAllocator);
        vm.expectRevert(ErrorsLib.ZeroAbsoluteCap.selector);
        this.takeWithAccrual(offer, data, taker, address(0));

        submitAndCall(realVault, abi.encodeCall(IVaultV2.increaseAbsoluteCap, (idData, 0.5e18)));
        vm.expectRevert(ErrorsLib.AbsoluteCapExceeded.selector);
        this.takeWithAccrual(offer, data, taker, address(0));

        submitAndCall(realVault, abi.encodeCall(IVaultV2.increaseAbsoluteCap, (idData, 1e18)));
        vm.expectRevert(ErrorsLib.RelativeCapExceeded.selector);
        this.takeWithAccrual(offer, data, taker, address(0));

        submitAndCall(realVault, abi.encodeCall(IVaultV2.increaseRelativeCap, (idData, 1e18)));
        this.takeWithAccrual(offer, data, taker, address(0));
        assertEq(realVault.allocation(keccak256(idData)), 1e18, "config allocation after buy");

        sellUnits(offer.market, 1e18, MAX_TICK);
        assertEq(realVault.allocation(keccak256(idData)), 0, "config allocation after sell");
    }

    function testOnBuyAfterFullLossKeepsMarketTracked() public {
        Offer memory first = buy(1 days, 1e18);
        Offer memory offer = buy(7 days, 1e18);
        Offer memory last = buy(30 days, 1e18);
        bytes32 marketId = _marketId(offer.market);
        setMidnightCredit(marketId, address(adapter), 0);

        offer.group = bytes32("second buy");
        midnight.supplyCollateral(offer.market, 0, 1e18, taker);
        midnight.supplyCollateral(offer.market, 1, 1e18, taker);
        vm.expectEmit(address(adapter));
        emit IMidnightAdapterBase.Buy(marketId, 1e18, 1e18, 1e18, 0);
        take(offer);

        uint128 netCredit = adapter.marketData(marketId).netCredit;
        assertEq(netCredit, 1e18, "netCredit");
        assertEq(adapter.realAssets(), 3e18, "realAssets");
        assertMarkets([_marketId(first.market), marketId, _marketId(last.market)]);
    }

    function testOnBuyZeroUnitsAfterFullLossRemovesMarket() public {
        Offer memory first = buy(1 days, 1e18);
        Offer memory offer = buy(7 days, 1e18, discountTick);
        Offer memory last = buy(30 days, 1e18);
        bytes32 marketId = _marketId(offer.market);
        MarketData memory expected = adapter.marketData(marketId);
        expected.netCredit = 0;
        expected.growth = 0;
        expected.maturity = 0;
        expected.index = 0;
        setMidnightCredit(marketId, address(adapter), 0);

        offer.group = bytes32("zero buy");
        bytes memory data = ratify([offer], signerAllocator);
        vm.expectEmit(address(adapter));
        emit IMidnightAdapterBase.Buy(marketId, 0, 0, 0, 0);
        vm.prank(taker);
        midnight.take(offer, data, 0, taker, taker, address(0), "");

        assertEq(abi.encode(adapter.marketData(marketId)), abi.encode(expected));
        assertEq(adapter.totalNetCredit(), 2e18);
        assertEq(parentVault.allocation(adapter.adapterId()), 2e18);
        assertMarkets([_marketId(first.market), _marketId(last.market)]);
    }

    function testSellClearsFirstMarketAndReactivatesSlot() public {
        checkSellClearsMarketAndReactivatesSlot(0);
    }

    function testSellClearsMiddleMarketAndReactivatesSlot() public {
        checkSellClearsMarketAndReactivatesSlot(125);
    }

    function testSellClearsLastMarketAndReactivatesSlot() public {
        checkSellClearsMarketAndReactivatesSlot(249);
    }

    function checkSellClearsMarketAndReactivatesSlot(uint256 soldIndex) internal {
        Offer memory soldOffer;
        for (uint256 i = 0; i < 250; i++) {
            Offer memory offer = buy(1 days + i, 1e18);
            if (i == soldIndex) soldOffer = offer;
        }
        assertEq(adapter.marketIdsLength(), 250, "marketIdsLength before");
        assertMarketIndex(_marketId(soldOffer.market), soldIndex);

        parentVault.setTotalAssets(1e18);
        bytes32 movedMarket = adapter.marketIds(249);
        vm.expectEmit(address(adapter));
        emit IMidnightAdapterBase.Sell(_marketId(soldOffer.market), 1e18, 0, 0, 0);
        sell(soldOffer.market, 1e18);

        assertEq(abi.encode(adapter.marketData(_marketId(soldOffer.market))), abi.encode(MarketData(0, 0, 0, 0, 0, 0)));
        assertEq(adapter.marketIdsLength(), 249, "marketIdsLength after");
        if (soldIndex < 249) assertEq(adapter.marketIds(soldIndex), movedMarket, "last market moved");
        for (uint256 i = 0; i < 249; i++) {
            assertNotEq(adapter.marketIds(i), _marketId(soldOffer.market), "sold market removed");
        }

        Offer memory newOffer = buy(60 days, 1e18);

        assertEq(adapter.marketIdsLength(), 250, "marketIdsLength final");
        assertEq(adapter.marketIds(249), _marketId(newOffer.market), "new market appended");
        assertMarketIndex(_marketId(newOffer.market), 249);
    }

    function testMarketBackpointerAfterMoveAndReentry() public {
        Offer memory first = buy(7 days, 1e18, discountTick);
        Offer memory middle = buy(14 days, 1e18, discountTick);
        Offer memory last = buy(30 days, 1e18, discountTick);
        parentVault.setTotalAssets(1e18);

        sellUnits(middle.market, middle.maxUnits, MAX_TICK);
        assertMarketIndex(_marketId(last.market), 1);

        vm.prank(signerAllocator);
        adapter.withdrawToVault(last.market, 0);
        assertMarketIndex(_marketId(last.market), 1);

        sellUnits(last.market, last.maxUnits / 2, MAX_TICK);
        assertMarketIndex(_marketId(last.market), 1);
        sellUnits(last.market, last.maxUnits - last.maxUnits / 2, MAX_TICK);
        assertMarkets([_marketId(first.market)]);

        middle.group = bytes32("reentry");
        take(middle);
        assertMarketIndex(_marketId(middle.market), 1);
        assertMarkets([_marketId(first.market), _marketId(middle.market)]);
        sellUnits(middle.market, middle.maxUnits, MAX_TICK);
        assertMarkets([_marketId(first.market)]);
    }

    function testSynchronizationUsesProvidedMarket() public {
        Offer memory offer = makeBuyOffer(7 days, 1e18, MAX_TICK);
        bytes32 marketId = _marketId(offer.market);
        midnight.supplyCollateral(offer.market, 0, offer.maxUnits, taker);
        midnight.supplyCollateral(offer.market, 1, offer.maxUnits, taker);
        vm.mockCallRevert(address(midnight), abi.encodeCall(IMidnight.toMarket, (marketId)), "market refetched");

        take(offer);
        vm.clearMockedCalls();
        vm.mockCallRevert(address(midnight), abi.encodeCall(IMidnight.toMarket, (marketId)), "market refetched");
        sell(offer.market, 0.25e18);
        forceDeallocate(offer.market, 0.25e18);
        vm.prank(signerAllocator);
        adapter.withdrawToVault(offer.market, 0);

        assertEq(adapter.marketData(marketId).netCredit, 0.5e18, "synchronized without refetching the market");
    }

    /* MARKETS */

    function testMarketsCap() public {
        for (uint256 i = 1; i <= 250; i++) {
            buy(i, 1e18);
        }
        assertEq(adapter.marketIdsLength(), 250);
        assertEq(adapter.realAssets(), 250e18);

        Offer memory offer = makeBuyOffer(251, 1e18, MAX_TICK);
        midnight.supplyCollateral(offer.market, 0, 0.5e18, taker);
        midnight.supplyCollateral(offer.market, 1, 0.5e18, taker);
        vm.expectRevert(IMidnightAdapterBase.TooManyMarkets.selector);
        take(offer);
    }

    function testMarketsBuySell(uint256 boughtNum, uint256 soldNum) public {
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

        assertEq(adapter.marketIdsLength(), boughtNum - soldNum);
        assertEq(adapter.realAssets(), (boughtNum - soldNum) * 1e18);
    }

    function testOnBuyCanRealizeLoss() public {
        uint256 tick = TickLib.priceToTick(0.95e18, 4);
        uint256 duration = 7 days;
        uint256 assets = 1e18;

        Offer memory offer = makeBuyOffer(duration, assets, tick);
        uint256 units = offer.maxUnits;
        midnight.supplyCollateral(offer.market, 0, units, taker);
        midnight.supplyCollateral(offer.market, 1, units, taker);
        uint256 vaultBalanceBefore = loanToken.balanceOf(address(parentVault));
        take(offer);

        uint256 paid = vaultBalanceBefore - loanToken.balanceOf(address(parentVault));
        uint256 growth = (units - paid) * 1e18 / (units * duration);
        bytes32 marketId = _marketId(offer.market);
        uint256 loss = 0.5e18;
        stdstore.target(address(midnight)).sig("credit(bytes32,address)").with_key(marketId).with_key(address(adapter))
            .checked_write(units - loss);

        offer.group = bytes32("second");
        midnight.supplyCollateral(offer.market, 0, units, taker);
        midnight.supplyCollateral(offer.market, 1, units, taker);
        take(offer);

        uint256 expectedValue = 2 * units - loss - (2 * units - loss).mulDivUp(growth * duration, 1e18);
        assertEq(adapter.realAssets(), expectedValue);
        uint128 marketNetCredit = adapter.marketData(marketId).netCredit;
        assertEq(marketNetCredit, 2 * units - loss);
    }

    function testOnSellMaxSellRate() public {
        uint256 price = TickLib.tickToPrice(MAX_TICK - 4);
        uint256 maxSellRate = (1e18 - price).mulDivUp(1e18, price * 30 days);

        deal(address(loanToken), address(parentVault), 1e18);
        Offer memory offer = buy(32 days, 1e18);
        skip(2 days);
        setMaxSellRate(offer.market, maxSellRate);

        sellUnits(offer.market, 1e18, MAX_TICK - 4);

        uint128 marketNetCredit = adapter.marketData(_marketId(offer.market)).netCredit;
        assertEq(marketNetCredit, 0);
        assertEq(adapter.realAssets(), 0);
        assertEq(adapter.maxSellRate(keccak256(abi.encode(offer.market.collateralParams))), maxSellRate);
    }

    // Same maximum rate, reached through the allocator take path: taking a buy offer makes the adapter sell.
    function testTakeMaxSellRate() public {
        uint256 price = TickLib.tickToPrice(MAX_TICK - 4);
        uint256 maxSellRate = (1e18 - price).mulDivUp(1e18, price * 30 days);

        deal(address(loanToken), address(parentVault), 1e18);
        Offer memory offer = buy(32 days, 1e18);
        skip(2 days);
        setMaxSellRate(offer.market, maxSellRate);

        Offer memory buyOffer = makeExternalOffer(offer.market, true, 1e18, MAX_TICK - 4);
        vm.prank(signerAllocator);
        adapter.take(buyOffer, "", 1e18);

        uint128 marketNetCredit = adapter.marketData(_marketId(offer.market)).netCredit;
        assertEq(marketNetCredit, 0);
        assertEq(adapter.realAssets(), 0);
    }

    function testTakeRoundingShortfallFailsMaxSellRate() public {
        deal(address(loanToken), address(parentVault), 10);
        Offer memory offer = buy(30 days, 10, discountTick);
        assertEq(adapter.marketData(_marketId(offer.market)).netCredit, 10);
        assertEq(adapter.realAssets(), 9);
        parentVault.setTotalAssets(10);

        Offer memory buyOffer = makeExternalOffer(offer.market, true, 5, discountTick);
        uint256 maxSellRate = uint256(1e18).mulDivUp(1, 4 * 30 days);
        setMaxSellRate(offer.market, maxSellRate - 1);
        vm.expectRevert(IMidnightAdapterBase.SellRateTooHigh.selector);
        vm.prank(signerAllocator);
        adapter.take(buyOffer, "", 5);

        setMaxSellRate(offer.market, maxSellRate);
        vm.expectRevert(IMidnightAdapterBase.MaxShortfallExceeded.selector);
        vm.prank(signerAllocator);
        adapter.take(buyOffer, "", 5);

        assertEq(adapter.marketData(_marketId(offer.market)).netCredit, 10);
        assertEq(adapter.realAssets(), 9);
        assertEq(loanToken.balanceOf(address(parentVault)), 1);
    }

    function testMaxSellRateUsesNetCreditAndNetProceeds(bool takerSale) public {
        midnight.setDefaultContinuousFee(address(loanToken), MAX_CONTINUOUS_FEE);
        for (uint256 i = 0; i <= 6; i++) {
            midnight.setDefaultSettlementFee(address(loanToken), i, 10 * CBP);
        }
        Offer memory boughtOffer = buy(30 days, 1e18, discountTick);
        bytes32 marketId = _marketId(boughtOffer.market);
        skip(2 days);
        midnight.updatePosition(boughtOffer.market, address(adapter));
        uint256 soldCredit = midnight.credit(marketId, address(adapter));
        uint256 soldNetCredit = adapter.marketData(marketId).netCredit;
        uint256 sellerPrice = TickLib.tickToPrice(discountTick) - (takerSale ? 10 * CBP : 0);
        uint256 sellerAssets =
            takerSale ? soldCredit.mulDivDown(sellerPrice, 1e18) : soldCredit.mulDivUp(sellerPrice, 1e18);
        uint256 maxSellRate = (soldNetCredit - sellerAssets).mulDivUp(1e18, sellerAssets * 28 days);
        assertLt(soldNetCredit, soldCredit, "pending continuous fee released on sale");
        assertLt(
            maxSellRate, (soldCredit - sellerAssets).mulDivUp(1e18, sellerAssets * 28 days), "net rate below gross rate"
        );
        Offer memory offer = takerSale
            ? makeExternalOffer(boughtOffer.market, true, 1e18, discountTick)
            : makeSellOffer(boughtOffer.market, soldCredit, discountTick);
        deal(address(loanToken), taker, 2e18);
        uint256 vaultBalanceBefore = loanToken.balanceOf(address(parentVault));
        setMaxSellRate(offer.market, maxSellRate - 1);

        vm.expectRevert(IMidnightAdapterBase.SellRateTooHigh.selector);
        if (takerSale) {
            vm.prank(signerAllocator);
            adapter.take(offer, "", soldCredit);
        } else {
            take(offer);
        }

        setMaxSellRate(offer.market, maxSellRate);
        if (takerSale) {
            vm.prank(signerAllocator);
            adapter.take(offer, "", soldCredit);
        } else {
            take(offer);
        }

        assertEq(adapter.marketData(marketId).netCredit, 0, "position sold");
        assertEq(loanToken.balanceOf(address(parentVault)), vaultBalanceBefore + sellerAssets, "net proceeds");
        assertEq(
            adapter.maxSellRate(keccak256(abi.encode(offer.market.collateralParams))),
            maxSellRate,
            "maximum not consumed"
        );
    }

    function testMaxSellRateSharedAcrossMaturitiesAndNotConsumed() public {
        Offer memory first = buy(4 days, 2e18);
        Offer memory second = buy(3 days, 1e18);
        skip(2 days);
        uint256 maxSellRate = uint256(1e18).mulDivUp(1, 2 days);
        setMaxSellRate(first.market, maxSellRate);

        sellUnits(first.market, 0.01e18, MAX_TICK / 2);
        sellUnits(first.market, 0.01e18, MAX_TICK / 2);
        vm.expectRevert(IMidnightAdapterBase.SellRateTooHigh.selector);
        sellUnits(second.market, 1e18, MAX_TICK / 2);

        assertEq(adapter.marketData(_marketId(first.market)).netCredit, 1.98e18, "both sales accepted");
        assertEq(
            adapter.maxSellRate(keccak256(abi.encode(first.market.collateralParams))),
            maxSellRate,
            "maximum not consumed"
        );
        assertEq(adapter.marketData(_marketId(second.market)).netCredit, 1e18, "other market protected");
        setMaxSellRate(second.market, uint256(1e18).mulDivUp(1, 1 days));
        sellUnits(second.market, 0.01e18, MAX_TICK / 2);
        assertEq(adapter.marketData(_marketId(second.market)).netCredit, 0.99e18, "shared maximum updated");
    }

    function testMaxSellRateIsPerCollateralParams() public {
        Offer memory first = buy(2 days, 1e18);
        Offer memory second = makeBuyOffer(2 days, 1e18, MAX_TICK);
        second.market.collateralParams = storedSingleCollateral;
        second.group = bytes32("other collaterals");
        midnight.supplyCollateral(second.market, 0, second.maxUnits, taker);
        take(second);
        skip(1 days);
        setMaxSellRate(first.market, 1);
        setMaxSellRate(second.market, uint256(1e18).mulDivUp(1, 1 days));

        sellUnits(second.market, 0.01e18, MAX_TICK / 2);
        vm.expectRevert(IMidnightAdapterBase.SellRateTooHigh.selector);
        sellUnits(first.market, 1e18, MAX_TICK / 2);

        assertEq(adapter.marketData(_marketId(second.market)).netCredit, 0.99e18, "other collateral array reduced");
        assertEq(adapter.marketData(_marketId(first.market)).netCredit, 1e18, "original collateral array protected");
    }

    function testMaxSellRateBoundary(uint256 duration, uint256 assets, bool unlimitedRate) public {
        duration = bound(duration, 1, 365 days);
        assets = bound(assets, MIN_TEST_ASSETS, MAX_TEST_ASSETS);
        deal(storedCollaterals[0].token, address(this), 3 * assets);
        deal(storedCollaterals[1].token, address(this), 3 * assets);
        Offer memory offer = buy(duration, assets, MAX_TICK / 2 - DEFAULT_TICK_SPACING);
        uint256 soldCredit = offer.maxUnits;
        uint256 sellerAssets = soldCredit.mulDivUp(0.5e18, 1e18);
        uint256 rate = (soldCredit - sellerAssets).mulDivUp(1e18, sellerAssets * duration);
        deal(address(loanToken), taker, sellerAssets);
        setMaxSellRate(offer.market, rate - 1);

        vm.expectRevert(IMidnightAdapterBase.SellRateTooHigh.selector);
        sellUnits(offer.market, soldCredit, MAX_TICK / 2);

        setMaxSellRate(offer.market, unlimitedRate ? type(uint256).max : rate);
        sellUnits(offer.market, soldCredit, MAX_TICK / 2);
        assertEq(adapter.marketData(_marketId(offer.market)).netCredit, 0, "rate accepted");
    }

    function testMaxSellRateUsesRemainingDuration() public {
        Offer memory offer = buy(31 days, 2e18);
        skip(1 days);
        setMaxSellRate(offer.market, uint256(1e18).mulDivUp(1, 30 days));
        sellUnits(offer.market, 0.01e18, MAX_TICK / 2);

        skip(15 days);
        vm.expectRevert(IMidnightAdapterBase.SellRateTooHigh.selector);
        sellUnits(offer.market, 0.01e18, MAX_TICK / 2);

        setMaxSellRate(offer.market, uint256(1e18).mulDivUp(1, 15 days));
        sellUnits(offer.market, 0.01e18, MAX_TICK / 2);
        assertEq(adapter.marketData(_marketId(offer.market)).netCredit, 1.98e18, "remaining duration used");
    }

    function testMaxSellRateZeroPreventsBelowParSales(bool initiallySet, bool zeroProceeds, uint256 elapsed) public {
        Offer memory offer = buy(30 days, 1e18);
        uint256 tick = zeroProceeds ? 0 : MAX_TICK / 2;
        if (initiallySet) {
            setMaxSellRate(offer.market, 1);
            if (zeroProceeds) vm.expectRevert(stdError.arithmeticError);
            else vm.expectRevert(IMidnightAdapterBase.SellRateTooHigh.selector);
            sellUnits(offer.market, 1e18, tick);
            setMaxSellRate(offer.market, 0);
        }

        skip(bound(elapsed, 0, 30 days - 1));
        if (zeroProceeds) vm.expectRevert(stdError.arithmeticError);
        else vm.expectRevert(IMidnightAdapterBase.SellRateTooHigh.selector);
        sellUnits(offer.market, 1e18, tick);
        assertEq(adapter.marketData(_marketId(offer.market)).netCredit, 1e18, "zero prevents below-par sales");
    }

    function testSellMaturityBoundary(bool afterMaturity, bool zeroRate) public {
        setShortfallParams(1e18, 0);
        Offer memory offer = buy(30 days, 2e18);
        setMaxSellRate(offer.market, zeroRate ? 0 : 1);
        skip(30 days - 1);

        vm.expectRevert(IMidnightAdapterBase.SellRateTooHigh.selector);
        sellUnits(offer.market, 1e18, MAX_TICK / 2);
        assertEq(adapter.marketData(_marketId(offer.market)).netCredit, 2e18, "below-par sale rejected before maturity");
        sellUnits(offer.market, 1e18, MAX_TICK);
        assertEq(adapter.marketData(_marketId(offer.market)).netCredit, 1e18, "par sale accepted before maturity");

        skip(afterMaturity ? 2 : 1);
        sellUnits(offer.market, 0.5e18, MAX_TICK / 2);
        assertEq(adapter.marketData(_marketId(offer.market)).netCredit, 0.5e18, "below-par sale accepted from maturity");
        sellUnits(offer.market, 0.5e18, MAX_TICK);
        assertEq(adapter.marketData(_marketId(offer.market)).netCredit, 0, "par sale accepted from maturity");
    }

    function testSellFromMaturityChecksShortfall(bool takerSale, bool zeroProceeds, bool disableLimit, uint256 elapsed)
        public
    {
        if (disableLimit) setShortfallParams(1e18, 0);
        Offer memory boughtOffer = buy(30 days, 1e18);
        uint256 tick = zeroProceeds ? 0 : MAX_TICK / 2;
        Offer memory offer = takerSale
            ? makeExternalOffer(boughtOffer.market, true, 1e18, MAX_TICK)
            : makeSellOffer(boughtOffer.market, 1e18, tick);
        offer.tick = tick;
        offer.expiry = boughtOffer.market.maturity + 365 days;
        bytes memory data = takerSale ? bytes("") : ratify([offer], signerAllocator);
        skip(30 days + bound(elapsed, 0, 365 days));
        uint256 vaultBalanceBefore = loanToken.balanceOf(address(parentVault));

        if (!disableLimit) vm.expectRevert(IMidnightAdapterBase.MaxShortfallExceeded.selector);
        if (takerSale) {
            vm.prank(signerAllocator);
            adapter.take(offer, "", 1e18);
        } else {
            this.takeWithAccrual(offer, data, taker, address(0));
        }

        if (disableLimit) {
            assertEq(midnight.credit(_marketId(boughtOffer.market), address(adapter)), 0, "position sold");
            assertEq(adapter.marketData(_marketId(boughtOffer.market)).netCredit, 0, "netCredit cleared");
            assertEq(adapter.marketIdsLength(), 0, "market removed");
            assertEq(
                loanToken.balanceOf(address(parentVault)),
                vaultBalanceBefore + TickLib.tickToPrice(tick),
                "sale proceeds"
            );
        } else {
            assertEq(midnight.credit(_marketId(boughtOffer.market), address(adapter)), 1e18, "position unchanged");
            assertEq(adapter.marketData(_marketId(boughtOffer.market)).netCredit, 1e18, "netCredit unchanged");
            assertEq(adapter.marketIdsLength(), 1, "market retained");
            assertEq(loanToken.balanceOf(address(parentVault)), vaultBalanceBefore, "vault balance unchanged");
        }
    }

    function testMaxSellRateAllowsParAndNetPremium(bool continuousFee) public {
        if (continuousFee) midnight.setDefaultContinuousFee(address(loanToken), MAX_CONTINUOUS_FEE);
        Offer memory offer = buy(30 days, 1e18, discountTick);
        setMaxSellRate(offer.market, 0);
        deal(address(loanToken), taker, offer.maxUnits);

        sellUnits(offer.market, offer.maxUnits, MAX_TICK);
        assertEq(adapter.marketData(_marketId(offer.market)).netCredit, 0, "nonpositive rate accepted");
    }

    function testMaxSellRateZeroAllowsTakingParBuyOfferWithoutFees() public {
        Offer memory boughtOffer = buy(30 days, 1e18);
        bytes32 marketId = _marketId(boughtOffer.market);
        assertEq(adapter.maxSellRate(keccak256(abi.encode(boughtOffer.market.collateralParams))), 0);
        assertEq(midnight.settlementFee(marketId, 30 days), 0);
        (uint128 credit, uint128 pendingFee,) =
            midnight.updatePositionView(boughtOffer.market, marketId, address(adapter));
        assertEq(pendingFee, 0, "no credit fee");
        Offer memory offer = makeExternalOffer(boughtOffer.market, true, credit, MAX_TICK);
        uint256 vaultBalanceBefore = loanToken.balanceOf(address(parentVault));

        vm.prank(signerAllocator);
        adapter.take(offer, "", credit);

        assertEq(loanToken.balanceOf(address(parentVault)), vaultBalanceBefore + credit, "par proceeds");
        assertEq(adapter.marketData(marketId).netCredit, 0, "position sold");
    }

    function testMaxSellRateZeroAllowsTakingParBuyOfferWithReleasedCreditFee() public {
        midnight.setDefaultContinuousFee(address(loanToken), MAX_CONTINUOUS_FEE);
        for (uint256 i = 0; i <= 6; i++) {
            midnight.setDefaultSettlementFee(address(loanToken), i, 10 * CBP);
        }
        Offer memory boughtOffer = buy(30 days, 1e18, discountTick);
        bytes32 marketId = _marketId(boughtOffer.market);
        assertEq(adapter.maxSellRate(keccak256(abi.encode(boughtOffer.market.collateralParams))), 0);
        (uint128 credit, uint128 pendingFee,) =
            midnight.updatePositionView(boughtOffer.market, marketId, address(adapter));
        uint256 settlementFee = midnight.settlementFee(marketId, 30 days);
        assertGt(settlementFee, 0, "nonzero settlement fee");
        uint256 sellerAssets = uint256(credit).mulDivDown(1e18 - settlementFee, 1e18);
        assertGe(pendingFee, credit - sellerAssets, "released credit fee covers settlement fee");
        assertGe(sellerAssets, credit - pendingFee, "proceeds cover net credit sold");
        Offer memory offer = makeExternalOffer(boughtOffer.market, true, credit, MAX_TICK);
        uint256 vaultBalanceBefore = loanToken.balanceOf(address(parentVault));

        vm.prank(signerAllocator);
        adapter.take(offer, "", credit);

        assertEq(loanToken.balanceOf(address(parentVault)), vaultBalanceBefore + sellerAssets, "net proceeds");
        assertEq(adapter.marketData(marketId).netCredit, 0, "position sold");
        (, uint128 remainingPendingFee,) = midnight.updatePositionView(boughtOffer.market, marketId, address(adapter));
        assertEq(remainingPendingFee, 0, "credit fee released");
    }

    function testMaxSellRateZeroWithSettlementFee(bool continuousFee) public {
        if (continuousFee) midnight.setDefaultContinuousFee(address(loanToken), MAX_CONTINUOUS_FEE);
        for (uint256 i = 0; i <= 6; i++) {
            midnight.setDefaultSettlementFee(address(loanToken), i, 10 * CBP);
        }
        Offer memory boughtOffer = buy(30 days, 1e18, discountTick);
        Offer memory offer = makeExternalOffer(boughtOffer.market, true, boughtOffer.maxUnits, MAX_TICK);

        if (!continuousFee) vm.expectRevert(IMidnightAdapterBase.SellRateTooHigh.selector);
        vm.prank(signerAllocator);
        adapter.take(offer, "", boughtOffer.maxUnits);

        assertEq(adapter.marketData(_marketId(offer.market)).netCredit, continuousFee ? 0 : boughtOffer.maxUnits);
    }

    function testOutOfOrderInsertsStayTracked() public {
        Offer memory first = buy(3, 1e18);
        Offer memory second = buy(1, 1e18);
        Offer memory third = buy(2, 1e18);

        assertMarkets([_marketId(first.market), _marketId(second.market), _marketId(third.market)]);
    }

    function testMiddleMarketRemoval() public {
        Offer memory smallest = buy(1, 1e18);
        Offer memory middle = buy(2, 1e18);
        Offer memory largest = buy(3, 1e18);

        parentVault.setTotalAssets(1e18);
        sell(middle.market, 1e18);

        assertMarkets([_marketId(smallest.market), _marketId(largest.market)]);
    }

    function testMaturedMarketsRemainTracked() public {
        Offer memory first = buy(1, 1e18);
        Offer memory second = buy(2, 1e18);
        skip(3);
        assertEq(adapter.realAssets(), 2e18, "realAssets");
        assertMarkets([_marketId(first.market), _marketId(second.market)]);
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

        uint128 netCreditA = adapter.marketData(_marketId(offerA.market)).netCredit;
        uint128 netCreditB = adapter.marketData(_marketId(offerB.market)).netCredit;
        assertEq(netCreditA, assetsA, "netCredit A");
        assertEq(netCreditB, assetsB, "netCredit B");
        assertEq(adapter.realAssets(), assetsA + assetsB, "realAssets");
        assertMarkets([_marketId(offerA.market), _marketId(offerB.market)]);
    }

    function testSecondBuyOnSameMarketDoesNotReinsert() public {
        Offer memory first = buy(7 days, 1e18);

        Offer memory second = makeBuyOffer(7 days, 1e18, MAX_TICK);
        second.group = bytes32("second");
        midnight.supplyCollateral(second.market, 0, 0.5e18, taker);
        midnight.supplyCollateral(second.market, 1, 0.5e18, taker);
        take(second);

        assertMarkets([_marketId(first.market)]);
    }

    function testZeroUnitBuyDoesNotInsertMarket() public {
        Offer memory first = buy(1 days, 1e18);
        Offer memory offer = makeBuyOffer(7 days, 1e18, MAX_TICK);
        bytes memory data = ratify([offer], signerAllocator);
        vm.prank(taker);
        midnight.take(offer, data, 0, taker, taker, address(0), "");

        assertEq(abi.encode(adapter.marketData(_marketId(offer.market))), abi.encode(MarketData(0, 0, 0, 0, 0, 0)));
        assertEq(adapter.totalNetCredit(), 1e18);
        assertEq(parentVault.allocation(adapter.adapterId()), 1e18);
        assertMarkets([_marketId(first.market)]);
    }

    function testBuyEvent() public {
        Offer memory offer = makeBuyOffer(7 days, 1e18, MAX_TICK);
        midnight.supplyCollateral(offer.market, 0, offer.maxUnits, taker);
        midnight.supplyCollateral(offer.market, 1, offer.maxUnits, taker);
        vm.expectEmit(address(adapter));
        emit IMidnightAdapterBase.Buy(_marketId(offer.market), 1e18, 1e18, 1e18, 0);
        take(offer);
    }

    /* ACCRUAL */

    function testPurchaseDiscountAccruesLinearly() public {
        uint256 duration = 30 days;
        uint256 vaultBalanceBefore = loanToken.balanceOf(address(parentVault));
        Offer memory offer = buy(duration, 1e18, discountTick);
        uint256 paid = vaultBalanceBefore - loanToken.balanceOf(address(parentVault));
        uint256 interest = offer.maxUnits - paid;
        assertGt(interest, 0, "bought at a discount");
        uint256 growth = interest * 1e18 / (uint256(offer.maxUnits) * duration);

        assertEq(
            adapter.realAssets(), offer.maxUnits - uint256(offer.maxUnits).mulDivUp(growth * duration, 1e18), "at buy"
        );
        assertGe(adapter.realAssets(), paid, "rounding is realized immediately");
        assertLt(
            adapter.realAssets() - paid, uint256(offer.maxUnits).mulDivUp(duration, 1e18), "initial rounding is bounded"
        );
        skip(duration / 3);
        assertEq(
            adapter.realAssets(),
            offer.maxUnits - uint256(offer.maxUnits).mulDivUp(growth * (2 * duration / 3), 1e18),
            "a third of the way"
        );
        skip(2 * duration / 3);
        assertEq(adapter.realAssets(), offer.maxUnits, "net credit at maturity");
        skip(365 days);
        assertEq(adapter.realAssets(), offer.maxUnits, "flat after maturity");
    }

    function testSecondBuyAccruesExistingDiscount() public {
        uint256 vaultBalanceBefore = loanToken.balanceOf(address(parentVault));
        Offer memory first = buy(30 days, 1e18, discountTick);
        uint256 firstPaid = vaultBalanceBefore - loanToken.balanceOf(address(parentVault));
        uint256 firstGrowth = (first.maxUnits - firstPaid) * 1e18 / (uint256(first.maxUnits) * 30 days);
        skip(15 days);
        uint256 valueBefore = adapter.realAssets();
        vaultBalanceBefore = loanToken.balanceOf(address(parentVault));

        Offer memory second = makeBuyOffer(15 days, 2e18, TickLib.priceToTick(0.9e18, DEFAULT_TICK_SPACING));
        second.group = bytes32("second buy");
        assertEq(_marketId(first.market), _marketId(second.market), "same market");
        midnight.supplyCollateral(second.market, 0, second.maxUnits, taker);
        midnight.supplyCollateral(second.market, 1, second.maxUnits, taker);
        take(second);

        uint256 paid = vaultBalanceBefore - loanToken.balanceOf(address(parentVault));
        uint256 totalNetCredit = uint256(first.maxUnits) + second.maxUnits;
        uint256 addedAssetsWadPerSecond = (second.maxUnits - paid).mulDivDown(1e18, 15 days);
        uint256 growth = (first.maxUnits * firstGrowth + addedAssetsWadPerSecond) / totalNetCredit;
        uint256 valueAfter = totalNetCredit - totalNetCredit.mulDivUp(growth * 15 days, 1e18);
        assertEq(adapter.realAssets(), valueAfter, "second purchase updates growth");
        assertGe(valueAfter, valueBefore + paid, "rounding is realized immediately");
        skip(15 days / 2);
        assertEq(
            adapter.realAssets(),
            totalNetCredit - totalNetCredit.mulDivUp(growth * (15 days / 2), 1e18),
            "combined discount accrues"
        );
        skip(15 days / 2);
        assertEq(adapter.realAssets(), totalNetCredit, "net credit at maturity");
    }

    function testWithdrawZeroPreservesAmortizedValue() public {
        uint256 vaultBalanceBefore = loanToken.balanceOf(address(parentVault));
        Offer memory offer = buy(30 days, 1e18, discountTick);
        uint256 paid = vaultBalanceBefore - loanToken.balanceOf(address(parentVault));
        uint256 growth = (offer.maxUnits - paid) * 1e18 / (uint256(offer.maxUnits) * 30 days);
        skip(1 days);
        uint256 valueBefore = adapter.realAssets();

        uint256 allowance = uint256(offer.maxUnits).mulDivDown(adapter.maxShortfallRatio(), 1e18);
        vm.expectEmit(address(adapter));
        emit IMidnightAdapterBase.WithdrawToVault(_marketId(offer.market), 0, offer.maxUnits, allowance);
        vm.prank(signerAllocator);
        adapter.withdrawToVault(offer.market, 0);
        assertEq(adapter.shortfallAllowance(), allowance);
        assertEq(adapter.realAssets(), valueBefore, "no discount realized by synchronization");

        skip(1 days);
        uint256 expectedValue = offer.maxUnits - uint256(offer.maxUnits).mulDivUp(growth * 28 days, 1e18);
        assertEq(adapter.realAssets(), expectedValue, "growth unchanged by synchronization");
    }

    function testSaleAboveMaxSellRateReverts() public {
        deal(address(loanToken), address(parentVault), 1e18);
        Offer memory offer = buy(30 days, 1e18, discountTick);
        parentVault.setTotalAssets(1e18);
        uint256 sellTick = TickLib.priceToTick(0.93e18, DEFAULT_TICK_SPACING);

        uint256 price = TickLib.tickToPrice(discountTick);
        setMaxSellRate(offer.market, (1e18 - price).mulDivUp(1e18, price * 30 days));
        vm.expectRevert(IMidnightAdapterBase.SellRateTooHigh.selector);
        sellUnits(offer.market, offer.maxUnits / 2, sellTick);
    }

    function testSaleAtAmortizedCostAfterDefault() public {
        deal(address(loanToken), address(parentVault), 1e18);
        Offer memory offer = buy(30 days, 1e18, discountTick);
        parentVault.setTotalAssets(1e18);

        OracleMock(storedCollaterals[0].oracle).setPrice(ORACLE_PRICE_SCALE / 4);
        OracleMock(storedCollaterals[1].oracle).setPrice(ORACLE_PRICE_SCALE / 4);
        midnight.liquidate(offer.market, 0, 0, 0, taker, false, address(this), address(0), "");
        (uint128 credit,,) = midnight.updatePositionView(offer.market, _marketId(offer.market), address(adapter));

        // Round up to a tick covering the amortized value, including growth-rounding dust.
        uint256 sellTick = TickLib.priceToTick(adapter.realAssets().mulDivUp(1e18, credit), DEFAULT_TICK_SPACING);
        parentVault.setTotalAssets(adapter.realAssets() + loanToken.balanceOf(address(parentVault)));
        vm.expectRevert(IMidnightAdapterBase.SellRateTooHigh.selector);
        sellUnits(offer.market, credit, sellTick);

        setMaxSellRate(offer.market, type(uint256).max);
        sellUnits(offer.market, credit, sellTick);

        assertGe(loanToken.balanceOf(address(parentVault)), parentVault.totalAssets(), "vault assets covered");
        assertEq(adapter.realAssets(), 0, "position sold");
        assertLt(loanToken.balanceOf(address(parentVault)), 1e18, "market loss remains");
    }

    function testRealAssetsPastAllMaturities() public {
        Offer memory offerA = buy(7 days, 1e18, discountTick);
        Offer memory offerB = buy(30 days, 2e18, discountTick);
        Offer memory offerC = buy(90 days, 3e18, discountTick);
        skip(100 days);

        assertEq(adapter.realAssets(), offerA.maxUnits + offerB.maxUnits + offerC.maxUnits, "sum of net credits");
        assertMarkets([_marketId(offerA.market), _marketId(offerB.market), _marketId(offerC.market)]);
    }

    function testSellBeforeMaturityRemovesNetCredit() public {
        uint256 duration = 30 days;
        Offer memory offer = buy(duration, 1e18, discountTick);
        skip(duration / 2);
        uint256 valueBefore = adapter.realAssets();

        sell(offer.market, offer.maxUnits / 2);

        assertEq(
            adapter.realAssets(),
            valueBefore.mulDivDown(offer.maxUnits - offer.maxUnits / 2, offer.maxUnits),
            "proportional amortized value removed"
        );
        skip(duration / 2);
        assertEq(adapter.realAssets(), offer.maxUnits - offer.maxUnits / 2, "remaining net credit unchanged");
    }

    function testSellAllBeforeMaturity() public {
        Offer memory offer = buy(30 days, 1e18, discountTick);
        skip(10 days);
        deal(address(loanToken), taker, offer.maxUnits);

        sell(offer.market, offer.maxUnits);

        assertEq(adapter.realAssets(), 0, "realAssets");
        assertEq(adapter.marketIdsLength(), 0, "marketIdsLength");
    }

    function testRealAssetsUsesCachedNetCredit(uint256 elapsed) public {
        elapsed = bound(elapsed, 0, 60 days);
        midnight.setDefaultContinuousFee(address(loanToken), MAX_CONTINUOUS_FEE);
        uint256 vaultBalanceBefore = loanToken.balanceOf(address(parentVault));
        Offer memory offer = buy(30 days, 1e18, discountTick);
        bytes32 marketId = _marketId(offer.market);
        uint128 netCredit = adapter.marketData(marketId).netCredit;
        uint256 paid = vaultBalanceBefore - loanToken.balanceOf(address(parentVault));
        uint256 growth = (netCredit - paid) * 1e18 / (uint256(netCredit) * 30 days);

        skip(elapsed);
        (uint128 credit, uint128 pendingFee,) = midnight.updatePosition(offer.market, address(adapter));
        assertEq(credit - pendingFee, netCredit, "continuous fees preserve net credit");

        vm.mockCallRevert(address(midnight), abi.encodeCall(IMidnight.toMarket, (marketId)), "position read");
        uint256 timeToMaturity = offer.market.maturity.zeroFloorSub(block.timestamp);
        assertEq(
            adapter.realAssets(),
            netCredit - uint256(netCredit).mulDivUp(growth * timeToMaturity, 1e18),
            "growth unchanged by fee accrual"
        );
    }

    function testCurrentNetCreditMatchesMidnight(
        uint128 credit,
        uint128 pendingFee,
        uint128 lastLossFactor,
        uint128 lossFactor,
        uint256 elapsed
    ) public {
        pendingFee = uint128(bound(pendingFee, 0, credit));
        lossFactor = uint128(bound(lossFactor, lastLossFactor, type(uint128).max));
        elapsed = bound(elapsed, 0, 60 days);
        Offer memory offer = buy(30 days, 1e18, MAX_TICK);
        bytes32 marketId = _marketId(offer.market);

        stdstore.enable_packed_slots();
        setMidnightCredit(marketId, address(adapter), credit);
        stdstore.enable_packed_slots().target(address(midnight)).sig("pendingFee(bytes32,address)").with_key(marketId)
            .with_key(address(adapter)).checked_write(pendingFee);
        stdstore.enable_packed_slots().target(address(midnight)).sig("lastLossFactor(bytes32,address)")
            .with_key(marketId).with_key(address(adapter)).checked_write(lastLossFactor);
        stdstore.enable_packed_slots().target(address(midnight)).sig("lossFactor(bytes32)").with_key(marketId)
            .checked_write(lossFactor);

        skip(elapsed);
        (uint128 expectedCredit, uint128 expectedPendingFee,) =
            midnight.updatePositionView(offer.market, marketId, address(adapter));
        assertEq(adapter.midnightCredit(offer.market), expectedCredit, "same gross credit as Midnight");
        assertEq(adapter.realAssets(), expectedCredit - expectedPendingFee, "same net credit as Midnight");
    }

    function testCurrentNetCreditAcrossLossAndAccrual(uint256 units, uint256 fee, uint256 elapsed, bool fullLoss)
        public
    {
        units = bound(units, 1000, 100e18);
        fee = bound(fee, 0, MAX_CONTINUOUS_FEE);
        elapsed = bound(elapsed, 0, 60 days);
        midnight.setDefaultContinuousFee(address(loanToken), fee);
        uint256 vaultBalanceBefore = loanToken.balanceOf(address(parentVault));
        Offer memory offer = buy(30 days, units, discountTick);
        uint128 netCredit = adapter.marketData(_marketId(offer.market)).netCredit;
        uint256 paid = vaultBalanceBefore - loanToken.balanceOf(address(parentVault));
        uint256 growth = (netCredit - paid) * 1e18 / (uint256(netCredit) * 30 days);

        skip(elapsed);
        assertCurrentNetCredit(offer.market, growth);

        uint256 price = fullLoss ? 0 : ORACLE_PRICE_SCALE / 4;
        OracleMock(storedCollaterals[0].oracle).setPrice(price);
        OracleMock(storedCollaterals[1].oracle).setPrice(price);
        midnight.liquidate(offer.market, 0, 0, 0, taker, false, address(this), address(0), "");
        assertCurrentNetCredit(offer.market, growth);

        midnight.updatePosition(offer.market, address(adapter));
        assertCurrentNetCredit(offer.market, growth);

        skip(30 days);
        assertCurrentNetCredit(offer.market, growth);
    }

    function testRealAssetsLossFallbackAndCacheSynchronization(uint256 units) public {
        units = bound(units, 1000, 100e18);
        midnight.setDefaultContinuousFee(address(loanToken), MAX_CONTINUOUS_FEE);
        uint256 vaultBalanceBefore = loanToken.balanceOf(address(parentVault));
        Offer memory offer = buy(30 days, units, discountTick);
        bytes32 marketId = _marketId(offer.market);
        uint128 oldNetCredit = adapter.marketData(marketId).netCredit;
        uint256 paid = vaultBalanceBefore - loanToken.balanceOf(address(parentVault));
        uint256 growth = (oldNetCredit - paid) * 1e18 / (uint256(oldNetCredit) * 30 days);
        skip(15 days);

        OracleMock(storedCollaterals[0].oracle).setPrice(ORACLE_PRICE_SCALE / 4);
        OracleMock(storedCollaterals[1].oracle).setPrice(ORACLE_PRICE_SCALE / 4);
        midnight.liquidate(offer.market, 0, 0, 0, taker, false, address(this), address(0), "");

        (uint128 credit, uint128 pendingFee,) = midnight.updatePositionView(offer.market, marketId, address(adapter));
        uint256 expectedValue = credit - pendingFee - uint256(credit - pendingFee).mulDivUp(growth * 15 days, 1e18);
        assertLt(credit - pendingFee, oldNetCredit, "loss realized");
        assertEq(adapter.realAssets(), expectedValue, "exact loss-adjusted amortized value");
        assertEq(adapter.marketData(marketId).netCredit, oldNetCredit, "view does not update the cache");

        midnight.updatePosition(offer.market, address(adapter));
        assertEq(adapter.realAssets(), expectedValue, "permissionless position update");

        MarketData memory data = adapter.marketData(marketId);
        uint256 allowance = uint256(oldNetCredit).mulDivDown(adapter.maxShortfallRatio(), 1e18);
        vm.expectEmit(address(adapter));
        emit IMidnightAdapterBase.WithdrawToVault(marketId, 0, credit - pendingFee, allowance);
        vm.prank(signerAllocator);
        adapter.withdrawToVault(offer.market, 0);
        assertEq(adapter.shortfallAllowance(), allowance);
        vm.mockCallRevert(address(midnight), abi.encodeCall(IMidnight.toMarket, (marketId)), "position read");
        assertEq(adapter.realAssets(), expectedValue, "cached after synchronization");

        vm.record();
        assertEq(adapter.marketData(marketId).netCredit, credit - pendingFee, "netCredit");
        (bytes32[] memory reads,) = vm.accesses(address(adapter));
        assertEq(reads.length, 2, "one allocation slot and one ownership slot");
        uint256 packed = uint256(vm.load(address(adapter), reads[0]));
        assertEq(uint128(packed), credit - pendingFee, "packed net credit");
        uint256 packedShares = uint256(vm.load(address(adapter), reads[1]));
        assertEq(uint128(packedShares), data.totalShares, "packed total shares");
        assertEq(uint128(packedShares >> 128), data.vaultShares, "packed vault shares");
    }

    function testLossBeforeMaturityIsVisibleWithoutPing() public {
        uint256 duration = 30 days;
        Offer memory offer = buy(duration, 1e18, discountTick);
        bytes32 marketId = _marketId(offer.market);
        skip(duration / 2);
        uint256 valueBefore = adapter.realAssets();

        OracleMock(storedCollaterals[0].oracle).setPrice(ORACLE_PRICE_SCALE / 4);
        OracleMock(storedCollaterals[1].oracle).setPrice(ORACLE_PRICE_SCALE / 4);
        midnight.liquidate(offer.market, 0, 0, 0, taker, false, address(this), address(0), "");

        assertGt(midnight.lossFactor(marketId), midnight.lastLossFactor(marketId, address(adapter)));
        assertEq(midnight.credit(marketId, address(adapter)), offer.maxUnits, "position not updated");
        assertEq(adapter.marketData(marketId).netCredit, offer.maxUnits, "cap accounting not updated");
        uint256 valueAfter = adapter.realAssets();
        assertApproxEqAbs(valueAfter, valueBefore / 2, 2, "half the value is lost");
        skip(duration / 2);
        (uint128 credit, uint128 pendingFee,) = midnight.updatePositionView(offer.market, marketId, address(adapter));
        assertEq(adapter.realAssets(), credit - pendingFee, "net credit at maturity");
        assertGt(adapter.realAssets(), valueAfter, "remaining discount accrued");
    }

    function testRealAssetsSeesLossesAcrossMaturities() public {
        Offer[3] memory offers = [buy(0, 1e18), buy(7 days, 1e18), buy(30 days, 1e18)];
        OracleMock(storedCollaterals[0].oracle).setPrice(ORACLE_PRICE_SCALE / 4);
        OracleMock(storedCollaterals[1].oracle).setPrice(ORACLE_PRICE_SCALE / 4);
        skip(1);

        for (uint256 i = 0; i < offers.length; i++) {
            bytes32 marketId = _marketId(offers[i].market);
            midnight.liquidate(offers[i].market, 0, 0, 0, taker, false, address(this), address(0), "");

            assertEq(midnight.credit(marketId, address(adapter)), 1e18, "position not updated");
            assertEq(adapter.marketData(marketId).netCredit, 1e18, "cap accounting not updated");
            assertApproxEqAbs(adapter.realAssets(), 3e18 - (i + 1) * 0.5e18, offers.length, "loss visible");
        }
    }

    function testFullLossCanBeRemovedWithWithdrawZero() public {
        Offer memory offer = buy(7 days, 1e18);
        bytes32 marketId = _marketId(offer.market);
        OracleMock(storedCollaterals[0].oracle).setPrice(0);
        OracleMock(storedCollaterals[1].oracle).setPrice(0);
        midnight.liquidate(offer.market, 0, 0, 0, taker, false, address(this), address(0), "");

        assertEq(midnight.lossFactor(marketId), type(uint128).max, "total loss");
        assertEq(adapter.realAssets(), 0, "loss visible before cleanup");
        assertEq(adapter.marketIdsLength(), 1, "market still tracked");

        vm.expectEmit(address(adapter));
        emit IMidnightAdapterBase.WithdrawToVault(marketId, 0, 0, 0);
        vm.prank(signerAllocator);
        adapter.withdrawToVault(offer.market, 0);

        assertEq(adapter.marketIdsLength(), 0, "market removed");
        assertEq(adapter.marketData(marketId).netCredit, 0, "netCredit");
        assertEq(parentVault.allocation(adapter.adapterId()), 0, "allocation");
    }

    /* FEES */

    function testContinuousFeeIsNotALoss() public {
        midnight.setDefaultContinuousFee(address(loanToken), MAX_CONTINUOUS_FEE);
        uint256 duration = 30 days;
        Offer memory offer = buy(duration, 1e18, discountTick);
        bytes32 marketId = _marketId(offer.market);

        uint256 pendingFee = midnight.pendingFee(marketId, address(adapter));
        assertGt(pendingFee, 0, "pendingFee");
        uint128 netCredit = adapter.marketData(marketId).netCredit;
        assertEq(netCredit, offer.maxUnits - pendingFee, "net credit excludes the pending fee");

        // The fee accrues out of the credit and of the pending fee alike, so the net credit does not move.
        skip(duration / 2);
        uint256 valueBefore = adapter.realAssets();
        adapter.withdrawToVault(offer.market, 0);
        assertLt(midnight.pendingFee(marketId, address(adapter)), pendingFee, "fee accrued");
        uint128 netCreditAfter = adapter.marketData(marketId).netCredit;
        assertEq(netCreditAfter, netCredit, "net credit unchanged");
        assertEq(adapter.realAssets(), valueBefore, "no loss booked");

        skip(duration / 2);
        assertEq(adapter.realAssets(), netCredit, "net credit at maturity");
    }

    function testBuyAtLossReverts() public {
        midnight.setDefaultContinuousFee(address(loanToken), MAX_CONTINUOUS_FEE);
        // At par, the pending fee makes the net credit lower than the assets paid.
        Offer memory offer = makeBuyOffer(30 days, 1e18, MAX_TICK);
        midnight.supplyCollateral(offer.market, 0, 1e18, taker);
        midnight.supplyCollateral(offer.market, 1, 1e18, taker);
        vm.expectRevert(IMidnightAdapterBase.BuyAtLoss.selector);
        take(offer);
    }

    function testBuyPostMaturityReverts(uint256 elapsed) public {
        elapsed = bound(elapsed, 1, 365 days);
        Offer memory offer = makeBuyOffer(30 days, 1e18, MAX_TICK);
        offer.expiry = type(uint256).max;
        // The taker needs credit to sell: Midnight itself refuses new debt after maturity.
        Offer memory sellOffer = makeExternalOffer(offer.market, false, 1e18, MAX_TICK);
        deal(address(loanToken), taker, 1e18);
        vm.prank(taker);
        midnight.take(sellOffer, "", sellOffer.maxUnits, taker, address(0), address(0), "");
        skip(30 days + elapsed);

        vm.expectRevert(IMidnightAdapterBase.BuyPostMaturity.selector);
        take(offer);
    }

    /* CALLBACKS */

    function testOnBuyNotMidnight(address caller) public {
        vm.assume(caller != address(midnight));
        vm.prank(caller);
        vm.expectRevert(IMidnightAdapterBase.NotMidnight.selector);
        adapter.onBuy(bytes32(0), storedOffer.market, 0, 0, 0, address(adapter), "");
    }

    function testOnBuyNotSelf(address buyer) public {
        vm.assume(buyer != address(adapter));
        vm.prank(address(midnight));
        vm.expectRevert(IMidnightAdapterBase.NotSelf.selector);
        adapter.onBuy(bytes32(0), storedOffer.market, 0, 0, 0, buyer, "");
    }

    function testOnBuyFundsFromCallbackDataAdapter() public {
        AdapterMock fundingAdapter = new AdapterMock(address(parentVault));
        uint256 vaultBalance = loanToken.balanceOf(address(parentVault));
        parentVault.allocate(address(fundingAdapter), hex"", vaultBalance);
        assertEq(loanToken.balanceOf(address(parentVault)), 0, "vault has no idle assets");

        Offer memory offer = makeBuyOffer(30 days, 1e18, MAX_TICK);
        offer.callbackData = abi.encode(address(fundingAdapter), bytes(""));
        midnight.supplyCollateral(offer.market, 0, offer.maxUnits, taker);
        midnight.supplyCollateral(offer.market, 1, offer.maxUnits, taker);
        take(offer);

        uint128 netCredit = adapter.marketData(_marketId(offer.market)).netCredit;
        assertEq(netCredit, offer.maxUnits, "bought without idle assets");
        assertEq(loanToken.balanceOf(address(fundingAdapter)), vaultBalance - 1e18, "funding adapter funded the buy");
    }

    function testOnBuyWithoutFundingRouteReverts() public {
        parentVault.allocate(address(extraAssetsAdapter), hex"", loanToken.balanceOf(address(parentVault)));

        Offer memory offer = makeBuyOffer(30 days, 1e18, MAX_TICK);
        midnight.supplyCollateral(offer.market, 0, offer.maxUnits, taker);
        midnight.supplyCollateral(offer.market, 1, offer.maxUnits, taker);
        vm.expectRevert();
        take(offer);
    }

    function testOnSellNotMidnight(address caller) public {
        vm.assume(caller != address(midnight));
        vm.prank(caller);
        vm.expectRevert(IMidnightAdapterBase.NotMidnight.selector);
        adapter.onSell(bytes32(0), storedOffer.market, 0, 0, 0, address(adapter), address(adapter), "");
    }

    function testOnSellNotSelf(address seller) public {
        vm.assume(seller != address(adapter));
        vm.prank(address(midnight));
        vm.expectRevert(IMidnightAdapterBase.NotSelf.selector);
        adapter.onSell(bytes32(0), storedOffer.market, 0, 0, 0, seller, address(adapter), "");
    }

    function testDeallocateNotParentVault(address caller) public {
        vm.assume(caller != address(parentVault));
        vm.prank(caller);
        vm.expectRevert(IMidnightAdapterBase.NotAuthorized.selector);
        adapter.deallocate("", 0, bytes4(0), caller);
    }

    /// @dev Only the adapter can allocate and deallocate through the vault, so it cannot be a liquidity adapter.
    function testVaultAllocateAndDeallocateRevert() public {
        vm.expectRevert(IMidnightAdapterBase.SelfAllocationOnly.selector);
        parentVault.allocate(address(adapter), "", 0);
        vm.expectRevert(IMidnightAdapterBase.SelfAllocationOnly.selector);
        parentVault.deallocate(address(adapter), "", 0);
    }

    /* SET CONSUMED */

    function testSetConsumedNotAuthorized(address caller) public {
        vm.assume(!parentVault.isAllocator(caller) && !parentVault.isSentinel(caller));
        vm.prank(caller);
        vm.expectRevert(IMidnightAdapterBase.NotAuthorized.selector);
        adapter.setConsumed(bytes32(0), type(uint128).max);
    }

    function testSetConsumedCancelsGroup(bool sentinel) public {
        address caller = signerAllocator;
        if (sentinel) {
            caller = makeAddr("sentinel");
            stdstore.target(address(parentVault)).sig("isSentinel(address)").with_key(caller).checked_write(true);
        }
        Offer memory offer = makeBuyOffer(7 days, 1e18, MAX_TICK);
        vm.expectEmit(address(adapter));
        emit IMidnightAdapterBase.SetConsumed(caller, offer.group, type(uint128).max);
        vm.prank(caller);
        adapter.setConsumed(offer.group, type(uint128).max);
        assertEq(midnight.consumed(address(adapter), offer.group), type(uint128).max, "consumed");

        bytes memory data = ratify([offer], signerAllocator);
        vm.expectRevert(IMidnight.ConsumedUnits.selector);
        this.takeWithAccrual(offer, data, taker, address(0));
    }

    /* TAKE */

    function testTakeLoanAssetMismatch() public {
        Offer memory offer = storedOffer;
        offer.market.loanToken = address(rewardToken);
        vm.prank(signerAllocator);
        vm.expectRevert(IMidnightAdapterBase.LoanAssetMismatch.selector);
        adapter.take(offer, "", 0);
    }

    /// @dev Selling more than its credit would put the adapter in debt, which it has no collateral for.
    function testTakeMoreThanPositionReverts() public {
        Offer memory offer = buy(7 days, 1e18);
        Offer memory buyOffer = makeExternalOffer(offer.market, true, 2e18, MAX_TICK);

        vm.expectRevert(IMidnightAdapterBase.InsufficientVaultCredit.selector);
        vm.prank(signerAllocator);
        adapter.take(buyOffer, "", 2e18);
    }

    /* FORCE DEALLOCATE */

    function testClaimCreationNoTradeOrSettlementFee(uint256 assets) public {
        assets = bound(assets, 1, 1e18);
        midnight.setDefaultSettlementFee(address(loanToken), 0, 10 * CBP);
        Offer memory offer = buy(7 days, 1e18);
        bytes32 id = _marketId(offer.market);
        uint256 feeBefore = midnight.claimableSettlementFee(address(loanToken));
        deal(address(loanToken), address(this), loanToken.balanceOf(address(this)) + assets);
        loanToken.approve(address(adapter), assets);
        vm.expectEmit(address(adapter));
        emit IMidnightAdapterBase.ForceDeallocate(
            address(this), id, address(this), assets, assets * 1e9, -int256(assets), 0
        );
        parentVault.forceDeallocate(address(adapter), claimData(offer.market, address(this)), assets, address(this));
        MarketData memory _marketData = adapter.marketData(id);
        assertEq(midnight.credit(id, address(adapter)), 1e18);
        assertEq(adapter.midnightCredit(offer.market), 1e18, "includes vault and claim ownership");
        assertEq(midnight.credit(id, address(this)), 0);
        assertEq(adapter.claimShares(id, address(this)), assets * 1e9);
        assertEq(_marketData.totalShares - _marketData.vaultShares, assets * 1e9);
        assertEq(adapter.marketData(id).netCredit, 1e18 - assets);
        assertEq(midnight.claimableSettlementFee(address(loanToken)), feeBefore);
        assertEq(loanToken.balanceOf(address(adapter)), 0);
    }

    /// @dev Stateful fuzzing: interleave allocation, exits, repayments, and redemptions for two holders.
    function testClaimOwnershipStateMachine(uint256 seed) public {
        Offer memory offer = buy(7 days, 10e18);
        Market memory market = offer.market;
        bytes32 id = _marketId(market);
        for (uint256 i; i < 24; i++) {
            seed = uint256(keccak256(abi.encode(seed, i)));
            MarketData memory _marketData = adapter.marketData(id);
            uint256 credit = midnight.credit(id, address(adapter));
            uint256 vaultCredit =
                _marketData.totalShares == 0 ? 0 : credit.mulDivDown(_marketData.vaultShares, _marketData.totalShares);
            uint256 liquidity = midnight.withdrawable(id);
            uint256 action = seed % 6;
            if (action == 0) {
                buyAdditionalCredit(market, 1 + (seed >> 8) % 1e18);
            } else if (action == 1 && vaultCredit > 0) {
                uint256 amount = 1 + (seed >> 8) % vaultCredit;
                deal(address(loanToken), address(this), loanToken.balanceOf(address(this)) + amount);
                loanToken.approve(address(adapter), amount);
                parentVault.forceDeallocate(
                    address(adapter), claimData(market, i % 2 == 0 ? address(this) : recipient), amount, address(this)
                );
            } else if (action == 2 && midnight.debt(id, taker) > 0) {
                uint256 amount = 1 + (seed >> 8) % midnight.debt(id, taker);
                deal(address(loanToken), taker, loanToken.balanceOf(taker) + amount);
                vm.prank(taker);
                midnight.repay(market, amount, taker, address(0), "");
            } else if (action == 3 && liquidity > 0 && vaultCredit > 0) {
                adapter.withdrawToVault(market, MathLib.min(liquidity, vaultCredit));
            } else if (action == 4 && liquidity > 0 && credit > 0) {
                address holder = i % 2 == 0 ? address(this) : recipient;
                uint256 shares =
                    MathLib.min(adapter.claimShares(id, holder), liquidity.mulDivDown(_marketData.totalShares, credit));
                if (shares > 0 && claimAssets(market, shares) > 0) {
                    vm.prank(holder);
                    adapter.redeemClaim(market, shares, holder);
                }
            } else if (action == 5 && vaultCredit > 0) {
                uint256 amount = 1 + (seed >> 8) % vaultCredit;
                deal(address(loanToken), taker, loanToken.balanceOf(taker) + amount);
                sell(market, amount);
            }
            _marketData = adapter.marketData(id);
            uint256 a = adapter.claimShares(id, address(this));
            uint256 b = adapter.claimShares(id, recipient);
            assertEq(uint256(_marketData.vaultShares) + a + b, _marketData.totalShares, "ownership conservation");
            uint256 accounted = adapter.realAssets() + claimAssets(market, a) + claimAssets(market, b);
            assertApproxEqAbs(accounted, midnight.credit(id, address(adapter)), 3, "credit conservation");
            assertEq(
                parentVault.allocation(adapter.adapterId()), adapter.marketData(id).netCredit, "reported allocation"
            );
            assertEq(loanToken.balanceOf(address(adapter)), 0, "no claim cash custody");
            assertEq(midnight.debt(id, address(adapter)), 0, "no adapter debt");
        }
    }

    function testClaimCreationBoundsAndRollback(uint256 failure) public {
        failure = bound(failure, 0, 2);
        Offer memory offer = buy(7 days, 1e18);
        bytes32 id = _marketId(offer.market);
        deal(address(loanToken), address(this), 2e18);
        loanToken.approve(address(adapter), failure == 2 ? 0 : 2e18);
        uint256 assets = failure == 0 ? 2e18 : 0.5e18;
        if (failure == 1) offer.market.loanToken = address(rewardToken);
        bytes4 errorSelector = failure == 0
            ? IMidnightAdapterBase.InsufficientVaultCredit.selector
            : failure == 1 ? IMidnightAdapterBase.LoanAssetMismatch.selector : ErrorsLib.TransferFromReverted.selector;
        vm.expectRevert(errorSelector);
        parentVault.forceDeallocate(address(adapter), abi.encode(offer.market, address(this)), assets, address(this));
        MarketData memory _marketData = adapter.marketData(id);
        assertEq(_marketData.totalShares, _marketData.vaultShares);
        assertEq(adapter.claimShares(id, address(this)), 0);
        assertEq(adapter.realAssets(), 1e18);
        assertEq(loanToken.balanceOf(address(this)), 2e18);
    }

    function testClaimCreationRoundsAssetLimitDown() public {
        Offer memory offer = buy(7 days, 4);
        bytes32 id = _marketId(offer.market);
        forceDeallocate(offer.market, 2);
        // A loss leaves 3 credit, half owned by the vault: its exit limit is 1, not 2.
        setMidnightCredit(id, address(adapter), 3);
        deal(address(loanToken), address(this), 2);
        loanToken.approve(address(adapter), 2);
        vm.expectRevert(IMidnightAdapterBase.InsufficientVaultCredit.selector);
        parentVault.forceDeallocate(address(adapter), claimData(offer.market, address(this)), 2, address(this));

        parentVault.forceDeallocate(address(adapter), claimData(offer.market, address(this)), 1, address(this));
        uint256 shares = uint256(4e9) / 3;
        MarketData memory data = adapter.marketData(id);
        assertEq(data.totalShares, 4e9);
        assertEq(data.vaultShares, 2e9 - shares);
        assertEq(adapter.claimShares(id, address(this)), 2e9 + shares);
        assertEq(loanToken.balanceOf(address(this)), 1);

        // The remaining vault shares cannot currently fund another whole cash unit.
        vm.expectRevert(IMidnightAdapterBase.InsufficientVaultCredit.selector);
        parentVault.forceDeallocate(address(adapter), claimData(offer.market, address(this)), 1, address(this));
        assertEq(adapter.marketData(id).vaultShares, data.vaultShares);
    }

    function testDirectRedemptionPartialAndFull(uint256 funded, uint256 firstShares) public {
        funded = bound(funded, 2, 1e18);
        Offer memory offer = buy(7 days, 1e18);
        bytes32 id = _marketId(offer.market);
        forceDeallocate(offer.market, funded);
        uint256 shares = adapter.claimShares(id, address(this));
        firstShares = bound(firstShares, 1e9, shares - 1e9);
        vm.prank(taker);
        midnight.repay(offer.market, funded, taker, address(0), "");
        vm.expectEmit(address(adapter));
        emit IMidnightAdapterBase.RedeemClaim(address(this), id, recipient, firstShares / 1e9, firstShares);
        uint256 paid = adapter.redeemClaim(offer.market, firstShares, recipient);
        paid += adapter.redeemClaim(offer.market, shares - firstShares, recipient);
        assertLe(paid, funded);
        assertApproxEqAbs(paid, funded, 2);
        assertEq(loanToken.balanceOf(recipient), paid);
        assertEq(loanToken.balanceOf(address(adapter)), 0);
        assertEq(adapter.claimShares(id, address(this)), 0);
        assertGe(adapter.realAssets(), 1e18 - funded);
        assertEq(adapter.marketData(id).netCredit, 1e18 - funded, "reporting checkpoint retained");
    }

    function testDirectRedemptionLiquidityAndAuthorizationRollback() public {
        Offer memory offer = buy(7 days, 1e18);
        bytes32 id = _marketId(offer.market);
        forceDeallocate(offer.market, 0.5e18);
        MarketData memory _marketData = adapter.marketData(id);
        uint256 shares = adapter.claimShares(id, address(this));
        vm.expectRevert(stdError.arithmeticError);
        adapter.redeemClaim(offer.market, shares, recipient);
        assertEq(adapter.claimShares(id, address(this)), shares);
        assertEq(adapter.marketData(id).totalShares, _marketData.totalShares);
        vm.prank(taker);
        midnight.repay(offer.market, 0.5e18, taker, address(0), "");
        vm.prank(recipient);
        vm.expectRevert(IMidnightAdapterBase.InsufficientClaimShares.selector);
        adapter.redeemClaim(offer.market, shares, recipient);
        adapter.redeemClaim(offer.market, shares, recipient);
        vm.expectRevert(IMidnightAdapterBase.InsufficientClaimShares.selector);
        adapter.redeemClaim(offer.market, shares, recipient);
    }

    /// forge-config: default.isolate = true
    function testGateBlockedAtomicExitAndIndependentRedemption() public {
        setUpRealVault();
        address gate = makeAddr("enter gate");
        vm.etch(gate, hex"01");
        vm.mockCall(gate, abi.encodeWithSelector(IEnterGate.canIncreaseCredit.selector), abi.encode(true));
        vm.mockCall(gate, abi.encodeWithSelector(IEnterGate.canIncreaseDebt.selector), abi.encode(true));
        storedOffer.market.enterGate = gate;
        bytes memory gateId = abi.encode("enterGate", gate);
        submitAndCall(realVault, abi.encodeCall(IVaultV2.increaseAbsoluteCap, (gateId, type(uint128).max)));
        submitAndCall(realVault, abi.encodeCall(IVaultV2.increaseRelativeCap, (gateId, 1e18)));
        Offer memory offer = buyOnRealVault(7 days, 10e18);
        assertEq(loanToken.balanceOf(address(realVault)), 0, "fully illiquid vault");
        vm.mockCallRevert(gate, abi.encodeWithSelector(IEnterGate.canIncreaseCredit.selector), "entry denied");
        // Temporary funding is recovered by the principal withdrawal in the same call.
        forceDeallocateOnRealVault(offer.market, 5e18);
        realVault.withdraw(5e18, address(this), address(this));
        assertEq(loanToken.balanceOf(address(this)), 5e18, "temporary principal recovered");
        assertEq(midnight.credit(_marketId(offer.market), address(this)), 0);
        submitAndCall(realVault, abi.encodeCall(IVaultV2.setIsAllocator, (address(adapter), false)));
        submitAndCall(realVault, abi.encodeCall(IVaultV2.removeAdapter, (address(adapter))));
        vm.prank(taker);
        midnight.repay(offer.market, 5e18, taker, address(0), "");
        bytes32 id = _marketId(offer.market);
        vm.mockCallRevert(address(realVault), bytes(""), bytes("vault unavailable"));
        adapter.redeemClaim(offer.market, adapter.claimShares(id, address(this)), recipient);
        assertEq(loanToken.balanceOf(recipient), 5e18);
    }

    function testClaimSurvivesActiveMarketRemovalAndPositionReuse() public {
        Offer memory offer = buy(7 days, 1e18);
        bytes32 id = _marketId(offer.market);
        forceDeallocate(offer.market, 1e18);
        MarketData memory _marketData = adapter.marketData(id);
        assertEq(adapter.marketIdsLength(), 0);
        assertEq(adapter.realAssets(), 0);
        assertEq(adapter.midnightCredit(offer.market), 1e18, "credit remains after active-market removal");
        vm.prank(taker);
        midnight.repay(offer.market, 1e18, taker, address(0), "");
        adapter.redeemClaim(offer.market, _marketData.totalShares, recipient);
        assertEq(adapter.marketData(id).totalShares, 0);
        buyAdditionalCredit(offer.market, 1e18);
        vm.expectRevert(IMidnightAdapterBase.InsufficientClaimShares.selector);
        adapter.redeemClaim(offer.market, _marketData.totalShares, recipient);
        assertEq(adapter.realAssets(), 1e18);
    }

    function testOldClaimsCanRedeemNewCreditAfterRoundingLoss() public {
        Offer memory offer = buy(7 days, 1);
        bytes32 id = _marketId(offer.market);
        forceDeallocate(offer.market, 1);
        uint256 shares = adapter.claimShares(id, address(this));

        // A partial market loss rounds this position to zero without disabling trading.
        stdstore.enable_packed_slots().target(address(midnight)).sig("lossFactor(bytes32)").with_key(id)
            .checked_write(type(uint128).max / 2);
        (uint128 credit,,) = midnight.updatePositionView(offer.market, id, address(adapter));
        assertEq(credit, 0);
        assertLt(midnight.lossFactor(id), type(uint128).max);
        assertEq(claimAssets(offer.market, shares), 0);

        buyAdditionalCredit(offer.market, 1);
        assertEq(claimAssets(offer.market, shares), 1);
        vm.prank(taker);
        midnight.repay(offer.market, 1, taker, address(0), "");
        uint256 balanceBefore = loanToken.balanceOf(recipient);
        assertEq(adapter.redeemClaim(offer.market, shares, recipient), 1);
        assertEq(loanToken.balanceOf(recipient) - balanceBefore, 1);
        assertEq(adapter.claimShares(id, address(this)), 0);
        assertEq(midnight.credit(id, address(adapter)), 0);
        // Accepted limitation: old claims consume the new vault backing without burning vault shares.
        MarketData memory _marketData = adapter.marketData(id);
        assertEq(_marketData.totalShares, 0);
        assertEq(_marketData.vaultShares, shares);
    }

    function testClaimTransferFailureRollsBackBurn() public {
        Offer memory offer = buy(7 days, 1e18);
        bytes32 id = _marketId(offer.market);
        forceDeallocate(offer.market, 1e18);
        MarketData memory _marketData = adapter.marketData(id);
        vm.prank(taker);
        midnight.repay(offer.market, 1e18, taker, address(0), "");
        vm.mockCallRevert(
            address(loanToken), abi.encodeCall(IERC20.transfer, (recipient, 1e18)), bytes("transfer failed")
        );
        vm.expectRevert();
        adapter.redeemClaim(offer.market, _marketData.totalShares, recipient);
        assertEq(adapter.marketData(id).totalShares, _marketData.totalShares);
        assertEq(adapter.claimShares(id, address(this)), _marketData.totalShares);
        assertEq(midnight.credit(id, address(adapter)), 1e18);
        assertEq(midnight.withdrawable(id), 1e18);
    }

    /// forge-config: default.isolate = true
    function testPenaltyFailureRollsBackClaimAndFunding() public {
        setUpRealVault();
        Offer memory offer = buyOnRealVault(7 days, 1e18);
        bytes32 id = _marketId(offer.market);
        deal(address(loanToken), taker, 1e18);
        vm.startPrank(taker);
        loanToken.approve(address(adapter), 1e18);
        vm.expectRevert(stdError.arithmeticError);
        realVault.forceDeallocate(address(adapter), claimData(offer.market, taker), 1e18, taker);
        vm.stopPrank();
        MarketData memory _marketData = adapter.marketData(id);
        assertEq(_marketData.vaultShares, _marketData.totalShares);
        assertEq(adapter.claimShares(id, taker), 0);
        assertEq(loanToken.balanceOf(taker), 1e18);
        assertEq(adapter.realAssets(), 1e18);
    }

    function testPendingFeeRedemptionNoImmediateProfit(uint256 fee, uint256 elapsed) public {
        fee = bound(fee, 0, MAX_CONTINUOUS_FEE);
        elapsed = bound(elapsed, 0, 7 days);
        midnight.setDefaultContinuousFee(address(loanToken), fee);
        Offer memory offer = makeBuyOffer(7 days, 1e18, discountTick);
        midnight.supplyCollateral(offer.market, 0, 2e18, taker);
        take(offer);
        skip(elapsed);
        bytes32 id = _marketId(offer.market);
        (uint128 gross,,) = midnight.updatePositionView(offer.market, id, address(adapter));
        uint256 funded = gross / 2;
        forceDeallocate(offer.market, funded);
        uint256 shares = adapter.claimShares(id, address(this));
        vm.prank(taker);
        midnight.repay(offer.market, funded, taker, address(0), "");
        uint256 vaultBefore = adapter.realAssets();
        uint256 cash = adapter.redeemClaim(offer.market, shares, recipient);
        assertLe(cash, funded);
        assertGe(adapter.realAssets(), vaultBefore);
        assertEq(loanToken.balanceOf(recipient), cash);
    }

    function testAllocatorCannotSpendClaims(bool makerSale) public {
        Offer memory offer = buy(7 days, 1e18);
        Offer memory signedSale = makeSellOffer(offer.market, 0.75e18, MAX_TICK);
        bytes memory signature = ratify([signedSale], signerAllocator);
        forceDeallocate(offer.market, 0.5e18);
        if (makerSale) {
            vm.prank(taker);
            vm.expectRevert(IMidnightAdapterBase.InsufficientVaultCredit.selector);
            midnight.take(signedSale, signature, signedSale.maxUnits, taker, address(0), address(0), "");
        } else {
            Offer memory externalBuy = makeExternalOffer(offer.market, true, 0.75e18, MAX_TICK);
            vm.prank(signerAllocator);
            vm.expectRevert(IMidnightAdapterBase.InsufficientVaultCredit.selector);
            adapter.take(externalBuy, "", externalBuy.maxUnits);
        }
        vm.prank(taker);
        midnight.repay(offer.market, 1e18, taker, address(0), "");
        vm.expectRevert(IMidnightAdapterBase.InsufficientVaultCredit.selector);
        adapter.withdrawToVault(offer.market, 0.75e18);
        adapter.withdrawToVault(offer.market, 0.5e18);
        bytes32 id = _marketId(offer.market);
        MarketData memory _marketData = adapter.marketData(id);
        adapter.redeemClaim(offer.market, _marketData.totalShares, recipient);
        assertEq(midnight.credit(id, address(adapter)), 0);
    }

    function testPurchasesAndSalesDoNotDiluteClaims(uint256 additional) public {
        additional = bound(additional, 1, 10e18);
        Offer memory offer = buy(7 days, 1e18);
        forceDeallocate(offer.market, 0.5e18);
        bytes32 id = _marketId(offer.market);
        uint256 shares = adapter.claimShares(id, address(this));
        buyAdditionalCredit(offer.market, additional);
        assertEq(claimAssets(offer.market, shares), 0.5e18);
        deal(address(loanToken), taker, 20e18);
        sell(offer.market, additional);
        assertEq(claimAssets(offer.market, shares), 0.5e18);
        assertEq(adapter.realAssets(), 0.5e18);
    }

    function testPurchaseUsesActualVaultCreditAfterShareRounding(bool par) public {
        Offer memory offer = buy(7 days, 8);
        bytes32 id = _marketId(offer.market);
        forceDeallocate(offer.market, 4);
        // A recognized loss leaves 6 credit, split equally between the two owners.
        setMidnightCredit(id, address(adapter), 6);
        Offer memory next = makeBuyOffer(7 days, par ? 1 : 2, MAX_TICK);
        next.group = bytes32("rounding purchase");
        if (par) {
            // The new unit rounds to the exit holder; the vault must not pay for it.
            vm.expectRevert(IMidnightAdapterBase.BuyAtLoss.selector);
            take(next);
            assertEq(adapter.realAssets(), 3);
        } else {
            next.tick = discountTick;
            take(next);
            // Two credit units were bought for one cash, but only one goes to the vault.
            assertEq(adapter.realAssets(), 4);
            assertEq(adapter.marketData(id).growth, 0, "no unearned vault interest");
        }
    }

    /// forge-config: default.isolate = true
    function testClaimsShareDefaultAndPreserveReportingCheckpoint(bool totalLoss) public {
        Offer memory offer = freshPosition(MAX_TICK);
        forceDeallocateOnRealVault(offer.market, 4e18);
        bytes32 id = _marketId(offer.market);
        uint256 shares = adapter.claimShares(id, address(this));
        this.realizeDefault(offer.market, totalLoss ? 0 : ORACLE_PRICE_SCALE / 2);
        uint256 cash = claimAssets(offer.market, shares);
        assertApproxEqAbs(cash, totalLoss ? 0 : 2e18, 2);
        assertApproxEqAbs(adapter.realAssets(), cash, 1);
        assertEq(adapter.marketData(id).netCredit, 4e18, "last reported allocation");
        if (totalLoss) {
            vm.expectRevert(IMidnightAdapterBase.ZeroClaimOutput.selector);
            adapter.redeemClaim(offer.market, shares, recipient);
        } else {
            vm.prank(taker);
            midnight.repay(offer.market, cash, taker, address(0), "");
            adapter.redeemClaim(offer.market, shares, recipient);
            assertEq(adapter.marketData(id).netCredit, 4e18, "redemption does not overwrite checkpoint");
        }
        adapter.withdrawToVault(offer.market, 0);
        assertApproxEqAbs(realVault.allocation(adapter.adapterId()), totalLoss ? 0 : 2e18, 2);
    }

    /// forge-config: default.isolate = true
    function testClaimRedemptionBlockedDuringSaleCallback() public {
        Offer memory offer = freshPosition(MAX_TICK);
        forceDeallocateOnRealVault(offer.market, 2e18);
        bytes32 id = _marketId(offer.market);
        EagerLossCallback callback = newCallback();
        callback.push(
            address(adapter),
            abi.encodeCall(IMidnightAdapterBase.redeemClaim, (offer.market, uint256(1e9), recipient)),
            IMidnightAdapterBase.SellInProgress.selector
        );
        callbackSale(makeSellOffer(offer.market, 4e18, MAX_TICK), callback);
        assertEq(adapter.marketData(id).netCredit, 2e18);
        assertEq(claimAssets(offer.market, 2e27), 2e18);
    }

    /// @dev Midnight takes its settlement fee out of the buyer's payment at any offer price, and rejects offers priced below the fee. The caller gets the seller's proceeds and pays the full amount to the vault.

    /// @dev The buyer pays the discounted price to the caller, who pays the full amount to the vault.

    function testForceDeallocateWithoutRole() public {
        Offer memory boughtOffer = buy(7 days, 1e18);
        skip(1);

        // Simulate the adapter having no role: any vault.deallocate call from the adapter reverts.
        vm.mockCallRevert(address(parentVault), abi.encodeWithSelector(VaultV2Mock.deallocate.selector), "no role");

        forceDeallocate(boughtOffer.market, 0.5e18);

        uint128 marketNetCredit = adapter.marketData(_marketId(boughtOffer.market)).netCredit;
        assertEq(marketNetCredit, 0.5e18, "netCredit");
    }

    /// forge-config: default.isolate = true
    /// @dev Runs on a real VaultV2, with a non-zero penalty, fees and maxRate, and with the adapter's allocator role revoked before the exit.
    function testForceDeallocateRealVaultWithPenalty() public {
        setUpRealVault();
        Offer memory offer = buyOnRealVault(7 days, 1e18);
        submitAndCall(realVault, abi.encodeCall(IVaultV2.setIsAllocator, (address(adapter), false)));

        skip(1);

        uint256 sharesBefore = realVault.balanceOf(address(this));
        uint256 expectedPenaltyShares = realVault.previewWithdraw(0.01e18);
        uint256 penaltyShares = forceDeallocateOnRealVault(offer.market, 0.5e18);

        assertEq(penaltyShares, expectedPenaltyShares, "penalty shares");
        assertEq(realVault.balanceOf(address(this)), sharesBefore - penaltyShares, "penalty charged to onBehalf");
        assertGt(realVault.balanceOf(recipient), 0, "fee shares minted");
        uint128 marketNetCredit = adapter.marketData(_marketId(offer.market)).netCredit;
        assertEq(marketNetCredit, 0.5e18, "netCredit");
        assertEq(loanToken.balanceOf(address(realVault)), 9.5e18, "vault balance");
    }

    /// forge-config: default.isolate = true
    function testForceDeallocateFromMaturity(bool afterMaturity) public {
        setUpRealVault();
        Offer memory offer = buyOnRealVault(7 days, 1e18);
        skip(7 days + (afterMaturity ? 1 : 0));

        forceDeallocateOnRealVault(offer.market, 1e18);

        assertEq(midnight.credit(_marketId(offer.market), address(adapter)), 1e18, "credit retained for claims");
        assertEq(adapter.marketIdsLength(), 0, "market removed");
        assertEq(realVault.allocation(adapter.adapterId()), 0, "allocation cleared");
        assertEq(loanToken.balanceOf(address(realVault)), 10e18, "full credit value returned to vault");
    }

    /// forge-config: default.isolate = true
    /// @dev A sendSharesGate blocking the adapter does not affect exits.
    function testForceDeallocateRealVaultWithGate() public {
        setUpRealVault();
        Offer memory offer = buyOnRealVault(7 days, 1e18);

        address gate = makeAddr("gate");
        vm.etch(gate, hex"01");
        vm.mockCall(gate, abi.encodeWithSelector(ISendSharesGate.canSendShares.selector), abi.encode(true));
        vm.mockCall(
            gate, abi.encodeWithSelector(ISendSharesGate.canSendShares.selector, address(adapter)), abi.encode(false)
        );
        submitAndCall(realVault, abi.encodeCall(IVaultV2.setSendSharesGate, (gate)));

        skip(1);

        forceDeallocateOnRealVault(offer.market, 0.5e18);
        assertEq(adapter.marketData(_marketId(offer.market)).netCredit, 0.5e18, "netCredit");
        assertEq(storedDurationAllocations(adapter)[0], 0.5e18, "1 day");
        assertEq(storedDurationAllocations(adapter)[1], 0, "7 days");
    }

    /// forge-config: default.isolate = true
    /// @dev An allocator takes external offers directly: taking a sell offer buys credit, taking a buy offer sells it. Both route through the same onBuy/onSell accounting as the maker flows.
    function testAllocatorTakeRealVault() public {
        setUpRealVault();
        Market memory market = makeBuyOffer(7 days, 1e18, MAX_TICK).market;
        bytes32 marketId = _marketId(market);

        Offer memory sellOffer = makeExternalOffer(market, false, 1e18, MAX_TICK);
        vm.expectRevert(IMidnightAdapterBase.NotAuthorized.selector);
        adapter.take(sellOffer, "", uint256(sellOffer.maxUnits));

        // Buy 1e18 credit by taking the external sell offer, funded by the vault.
        vm.prank(signerAllocator);
        adapter.take(sellOffer, "", uint256(sellOffer.maxUnits));

        assertEq(realVault.allocation(adapter.adapterId()), 1e18, "allocation after buy");
        assertEq(loanToken.balanceOf(address(realVault)), 9e18, "vault funded the buy");
        assertEq(adapter.realAssets(), 1e18, "adapter realAssets after buy");

        skip(1);

        // Sell 0.5e18 credit by taking an external buy offer, proceeds forwarded to the vault.
        Offer memory buyOffer = makeExternalOffer(market, true, 0.5e18, MAX_TICK);
        vm.prank(signerAllocator);
        adapter.take(buyOffer, "", uint256(buyOffer.maxUnits));

        uint128 marketNetCredit = adapter.marketData(marketId).netCredit;
        assertEq(marketNetCredit, 0.5e18, "netCredit after sell");
        assertEq(realVault.allocation(adapter.adapterId()), 0.5e18, "allocation after sell");
        assertEq(loanToken.balanceOf(address(realVault)), 9.5e18, "proceeds back in the vault");
    }

    /// forge-config: default.isolate = true
    function testMakerTakeWithoutAccrualInSameTransaction(bool isBuy) public {
        setUpRealVault();
        Offer memory boughtOffer = buyOnRealVault(7 days, 1e18);
        Offer memory offer;
        if (isBuy) {
            offer = makeBuyOffer(7 days, 1e18, MAX_TICK);
            offer.maker = address(adapter);
            offer.ratifier = address(adapter);
            offer.group = bytes32("second buy");
            midnight.supplyCollateral(offer.market, 0, 0.5e18, taker);
            midnight.supplyCollateral(offer.market, 1, 0.5e18, taker);
        } else {
            offer = makeSellOffer(boughtOffer.market, 1e18, MAX_TICK);
        }

        realVault.accrueInterest();
        assertEq(realVault.firstTotalAssets(), 0, "previous transaction does not count");
        bytes memory data = ratify([offer], signerAllocator);
        vm.prank(taker);
        midnight.take(offer, data, offer.maxUnits, taker, isBuy ? taker : address(0), address(0), "");

        assertEq(adapter.realAssets(), isBuy ? 2e18 : 0, "take succeeds without pre-accrual");
    }

    /// forge-config: default.isolate = true
    function testBuyerCallbackDepositUsesPreTradeSharePrice() public {
        setUpRealVault();
        Offer memory boughtOffer = buyOnRealVault(7 days, 1e18);
        Offer memory offer = makeSellOffer(boughtOffer.market, 1e18, MAX_TICK);
        deal(address(loanToken), address(this), 2e18);
        loanToken.approve(address(midnight), type(uint256).max);

        this.takeWithAccrual(offer, ratify([offer], signerAllocator), taker, address(this));

        assertEq(realVault.balanceOf(recipient), 1e18, "deposit at the pre-trade share price");
        assertEq(realVault.totalSupply(), 11e18, "total shares");
        assertEq(realVault.totalAssets(), 11e18, "settled vault assets");
        assertEq(adapter.realAssets(), 0, "position sold");
    }

    function onBuy(bytes32, Market memory, uint256, uint256, uint256, address, bytes memory)
        external
        returns (bytes32)
    {
        assertEq(msg.sender, address(midnight));
        vm.expectRevert(IMidnightAdapterBase.OtherSellInProgress.selector);
        adapter.realAssets();
        assertEq(loanToken.balanceOf(address(realVault)), 9e18, "payment has not arrived");
        assertEq(realVault.totalAssets(), 10e18, "vault valuation fixed before the trade");
        realVault.deposit(1e18, recipient);
        return CALLBACK_SUCCESS;
    }

    /// forge-config: default.isolate = true
    function testDepositAfterLossUsesUpdatedAssetsRealVault() public {
        setUpRealVault();
        Offer memory offer = buyOnRealVault(7 days, 1e18);
        bytes32 marketId = _marketId(offer.market);
        OracleMock(storedCollaterals[0].oracle).setPrice(ORACLE_PRICE_SCALE / 2);
        OracleMock(storedCollaterals[1].oracle).setPrice(ORACLE_PRICE_SCALE / 2);
        midnight.liquidate(offer.market, 0, 0, 0, taker, false, address(this), address(0), "");

        assertEq(midnight.credit(marketId, address(adapter)), 1e18, "position not updated");
        assertEq(adapter.marketData(marketId).netCredit, 1e18, "cap accounting not updated");
        assertApproxEqAbs(adapter.realAssets(), 0.5e18, 1, "adapter loss visible");
        assertApproxEqAbs(realVault.totalAssets(), 9.5e18, 1, "vault loss visible");
        uint256 expectedShares = 1e18 * (realVault.totalSupply() + 1) / (realVault.totalAssets() + 1);
        deal(address(loanToken), address(this), 1e18);

        uint256 shares = realVault.deposit(1e18, recipient);

        assertEq(shares, expectedShares, "deposit uses post-loss assets");
        assertGt(shares, 1e18, "more shares than at the pre-loss price");
        assertApproxEqAbs(realVault.totalAssets(), 10.5e18, 1, "assets after deposit");
        assertEq(midnight.credit(marketId, address(adapter)), 1e18, "no position ping needed");
    }

    /// forge-config: default.isolate = true
    /// @dev A market whose oracle permanently reverts cannot be abandoned beyond the shortfall allowance.
    function testCannotAbandonMarketWithRevertingOracleFromMaturity() public {
        setUpRealVault();
        Offer memory boughtOffer = buyOnRealVault(7 days, 1e18);
        bytes32 marketId = _marketId(boughtOffer.market);

        skip(7 days);
        vm.mockCallRevert(storedCollaterals[0].oracle, abi.encodeWithSignature("price()"), bytes("dead oracle"));

        vm.expectRevert(bytes("dead oracle"));
        midnight.liquidate(boughtOffer.market, 0, 0, 0, taker, true, address(this), address(0), "");
        assertEq(midnight.lossFactor(marketId), 0, "loss not realized");
        assertEq(realVault.totalAssets(), 10e18, "market still fully valued");
        assertEq(
            adapter.maxSellRate(keccak256(abi.encode(boughtOffer.market.collateralParams))), 0, "default maximum rate"
        );
        bytes32[] memory marketIds = adapter.ids(boughtOffer.market);
        for (uint256 i = 0; i < marketIds.length; i++) {
            assertEq(realVault.allocation(marketIds[i]), 1e18, "allocation");
        }

        address buyer = makeAddr("buyer");
        Offer memory sellOffer = makeSellOffer(boughtOffer.market, 1e18, 0);
        bytes memory data = ratify([sellOffer], signerAllocator);
        vm.expectRevert(IMidnightAdapterBase.MaxShortfallExceeded.selector);
        this.takeWithAccrual(sellOffer, data, buyer, address(0));

        assertEq(midnight.credit(marketId, address(adapter)), 1e18, "adapter credit unchanged");
        assertEq(midnight.credit(marketId, buyer), 0, "buyer received no credit");
        assertEq(adapter.marketIdsLength(), 1, "market retained");
        assertEq(adapter.realAssets(), 1e18, "adapter realAssets");
        assertEq(realVault.totalAssets(), 10e18, "market still fully valued");
        for (uint256 i = 0; i < marketIds.length; i++) {
            assertEq(realVault.allocation(marketIds[i]), 1e18, "allocation unchanged");
        }
    }

    /* WITHDRAW TO VAULT */

    function testWithdrawToVaultByAnyone(address caller) public {
        Offer memory boughtOffer = buy(7 days, 1e18);

        vm.prank(caller);
        adapter.withdrawToVault(boughtOffer.market, 0);
    }

    function testWithdrawToVaultOK(address caller) public {
        Offer memory boughtOffer = buy(7 days, 1e18);
        bytes32 marketId = _marketId(boughtOffer.market);
        uint128 creditBefore = adapter.marketData(marketId).netCredit;
        uint256 vaultBalanceBefore = loanToken.balanceOf(address(parentVault));

        skip(7 days);

        deal(address(loanToken), address(this), 1e18);
        loanToken.approve(address(midnight), type(uint256).max);
        midnight.repay(boughtOffer.market, 1e18, taker, address(0), "");

        uint256 withdrawAmount = 0.5e18;
        vm.expectEmit(address(adapter));
        emit IMidnightAdapterBase.WithdrawToVault(marketId, withdrawAmount, creditBefore - withdrawAmount, 0.005e18);
        vm.prank(caller);
        adapter.withdrawToVault(boughtOffer.market, withdrawAmount);
        assertEq(adapter.shortfallAllowance(), 0.005e18, "shortfallAllowance");

        uint128 creditAfter = adapter.marketData(marketId).netCredit;
        assertEq(creditAfter, creditBefore - withdrawAmount, "netCredit");
        assertEq(adapter.realAssets(), creditBefore - withdrawAmount, "realAssets");
        assertEq(loanToken.balanceOf(address(parentVault)), vaultBalanceBefore + withdrawAmount, "vault balance");
    }

    function testWithdrawToVaultAfterLoss() public {
        Offer memory boughtOffer = buy(7 days, 1e18);
        bytes32 marketId = _marketId(boughtOffer.market);

        // The borrower repays 0.7e18 and defaults on the rest.
        deal(address(loanToken), address(this), 0.7e18);
        loanToken.approve(address(midnight), type(uint256).max);
        midnight.repay(boughtOffer.market, 0.7e18, taker, address(0), "");
        OracleMock(storedCollaterals[0].oracle).setPrice(0);
        OracleMock(storedCollaterals[1].oracle).setPrice(0);
        midnight.liquidate(boughtOffer.market, 0, 0, 0, taker, false, address(this), address(0), "");
        skip(7 days);

        vm.prank(signerAllocator);
        adapter.withdrawToVault(boughtOffer.market, 0.5e18);

        // 0.5e18 withdrawn, 0.3e18 lost.
        uint128 netCredit = adapter.marketData(marketId).netCredit;
        assertApproxEqAbs(netCredit, 0.2e18, 1, "netCredit");
        assertApproxEqAbs(adapter.realAssets(), 0.2e18, 1, "realAssets");
        assertApproxEqAbs(parentVault.allocation(adapter.adapterId()), 0.2e18, 1, "allocation");
    }

    /* SKIM */

    function testSetSkimRecipientNotAuthorized(address caller) public {
        vm.assume(caller != curator);
        vm.expectRevert(IMidnightAdapterBase.NotAuthorized.selector);
        vm.prank(caller);
        adapter.submit(abi.encodeCall(IMidnightAdapterBase.setSkimRecipient, (recipient)));
    }

    function testSetSkimRecipientNotTimelocked() public {
        vm.expectRevert(IMidnightAdapterBase.DataNotTimelocked.selector);
        adapter.setSkimRecipient(recipient);
    }

    function testSetSkimRecipientTimelockNotExpired(uint256 timelockDuration) public {
        timelockDuration = bound(timelockDuration, 1, 3650 days);
        submitTimelock(IMidnightAdapterBase.setSkimRecipient.selector, timelockDuration);

        vm.prank(curator);
        adapter.submit(abi.encodeCall(IMidnightAdapterBase.setSkimRecipient, (recipient)));

        vm.expectRevert(IMidnightAdapterBase.TimelockNotExpired.selector);
        adapter.setSkimRecipient(recipient);
    }

    function testSetSkimRecipientOK() public {
        address newRecipient = makeAddr("newRecipient");
        setSkimRecipient(newRecipient);
        assertEq(adapter.skimRecipient(), newRecipient, "skimRecipient");
    }

    function testSkimUnauthorized(address caller) public {
        setSkimRecipient(recipient);
        vm.assume(caller != recipient);
        vm.prank(caller);
        vm.expectRevert(IMidnightAdapterBase.NotAuthorized.selector);
        adapter.skim(address(rewardToken));
    }

    function testSkimOK() public {
        setSkimRecipient(recipient);

        uint256 balance = 123e18;
        deal(address(rewardToken), address(adapter), balance);

        vm.expectEmit(true, false, false, true, address(adapter));
        emit IMidnightAdapterBase.Skim(address(rewardToken), balance);
        vm.prank(recipient);
        adapter.skim(address(rewardToken));

        assertEq(rewardToken.balanceOf(recipient), balance, "recipient received");
        assertEq(rewardToken.balanceOf(address(adapter)), 0, "adapter drained");
    }

    /* NET CREDIT BOUNDS */

    function testTotalNetCreditBounds() public {
        uint256 maxMarkets = adapter.MAX_MARKETS();
        uint256 maxTotalNetCredit = maxMarkets * type(uint128).max;
        assertLe(maxTotalNetCredit, type(uint136).max);
        assertLe((maxMarkets + 1) * type(uint128).max, type(uint136).max);
        deal(address(loanToken), address(parentVault), maxTotalNetCredit);
        deal(storedCollaterals[0].token, address(this), maxTotalNetCredit + type(uint128).max);
        deal(storedCollaterals[1].token, address(this), maxTotalNetCredit + type(uint128).max);

        Offer memory offer;
        for (uint256 i = 1; i <= maxMarkets; i++) {
            offer = buy(i, type(uint128).max);
            assertEq(adapter.totalNetCredit(), i * type(uint128).max);
        }
        assertEq(adapter.marketIdsLength(), maxMarkets);

        sellUnits(offer.market, type(uint128).max, MAX_TICK);
        assertEq(adapter.totalNetCredit(), maxTotalNetCredit - type(uint128).max);
        assertEq(adapter.marketIdsLength(), maxMarkets - 1);

        buy(maxMarkets + 1, type(uint128).max);
        assertEq(adapter.totalNetCredit(), maxTotalNetCredit);
        assertEq(adapter.marketIdsLength(), maxMarkets);
        assertEq(adapter.shortfallRefillPeriod(), 1 days);
        assertEq(adapter.shortfallUpdatedAt(), vm.getBlockTimestamp());
    }

    function testOnBuyNetCreditSumAboveUint128() public {
        Offer memory offer = buyMaxNetCredit();
        bytes32 marketId = _marketId(offer.market);

        OracleMock(storedCollaterals[0].oracle).setPrice(ORACLE_PRICE_SCALE / 4);
        OracleMock(storedCollaterals[1].oracle).setPrice(ORACLE_PRICE_SCALE / 4);
        midnight.liquidate(offer.market, 0, 0, 0, taker, false, address(this), address(0), "");
        (uint128 currentCredit,,) = midnight.updatePositionView(offer.market, marketId, address(adapter));
        OracleMock(storedCollaterals[0].oracle).setPrice(ORACLE_PRICE_SCALE);
        OracleMock(storedCollaterals[1].oracle).setPrice(ORACLE_PRICE_SCALE);

        uint256 boughtNetCredit = 1 << 126;
        uint256 expectedNetCredit = currentCredit + boughtNetCredit;
        assertGt(uint256(adapter.marketData(marketId).netCredit) + boughtNetCredit, type(uint128).max, "wide sum");
        assertLe(expectedNetCredit, type(uint128).max, "final credit fits");

        deal(address(loanToken), address(parentVault), boughtNetCredit);
        offer.maxUnits = uint128(boughtNetCredit);
        offer.group = bytes32("second buy");
        vm.expectEmit(address(adapter));
        emit IMidnightAdapterBase.Buy(marketId, boughtNetCredit, boughtNetCredit, expectedNetCredit, 0);
        take(offer);

        assertEq(adapter.marketData(marketId).netCredit, expectedNetCredit, "market netCredit");
        assertEq(adapter.realAssets(), expectedNetCredit, "realAssets");
        assertEq(parentVault.allocation(adapter.adapterId()), expectedNetCredit, "allocation");
    }

    function testOnSellMaxNetCredit() public {
        Offer memory offer = buyMaxNetCredit();
        bytes32 marketId = _marketId(offer.market);
        uint256 assets = uint256(type(uint128).max) - 1;

        vm.expectEmit(address(adapter));
        emit IMidnightAdapterBase.Sell(marketId, assets, 1, 0, 0);
        sell(offer.market, assets);

        assertEq(adapter.marketData(marketId).netCredit, 1, "market netCredit");
        assertEq(adapter.realAssets(), 1, "realAssets");
        assertEq(parentVault.allocation(adapter.adapterId()), 1, "allocation");
        assertEq(loanToken.balanceOf(address(parentVault)), assets, "vault balance");
    }

    function testForceDeallocateMaxNetCredit() public {
        Offer memory offer = buyMaxNetCredit();
        bytes32 id = _marketId(offer.market);
        forceDeallocate(offer.market, uint256(type(uint128).max) - 1);
        assertEq(adapter.marketData(id).netCredit, 1);
        assertEq(adapter.realAssets(), 1);
        assertEq(parentVault.allocation(adapter.adapterId()), 1);
    }

    function testWithdrawToVaultMaxNetCredit() public {
        Offer memory offer = buyMaxNetCredit();
        bytes32 marketId = _marketId(offer.market);
        uint256 assets = uint256(type(uint128).max) - 1;
        skip(7 days);

        vm.prank(taker);
        midnight.repay(offer.market, type(uint128).max, taker, address(0), "");
        vm.expectEmit(address(adapter));
        emit IMidnightAdapterBase.WithdrawToVault(
            marketId, assets, 1, uint256(type(uint128).max).mulDivDown(0.005e18, 1e18)
        );
        vm.prank(signerAllocator);
        adapter.withdrawToVault(offer.market, assets);
        assertEq(adapter.shortfallAllowance(), uint256(type(uint128).max).mulDivDown(0.005e18, 1e18), "allowance");

        assertEq(adapter.marketData(marketId).netCredit, 1, "market netCredit");
        assertEq(adapter.realAssets(), 1, "realAssets");
        assertEq(parentVault.allocation(adapter.adapterId()), 1, "allocation");
        assertEq(loanToken.balanceOf(address(parentVault)), assets, "vault balance");
    }

    /* SHORTFALL LIMITER */

    function testShortfallParamsDefaultToZero() public {
        VaultV2Mock newVault = new VaultV2Mock(address(loanToken), owner, curator, signerAllocator, address(0));
        IMidnightAdapter newAdapter = IMidnightAdapter(factory.createMidnightAdapter(address(newVault)));
        assertEq(newAdapter.maxShortfallRatio(), 0, "ratio");
        assertEq(newAdapter.shortfallRefillPeriod(), 0, "period");
    }

    function testSetMaxShortfallRatio(uint256 ratio) public {
        ratio = bound(ratio, 0, 1e18);
        vm.expectRevert(IMidnightAdapterBase.DataNotTimelocked.selector);
        adapter.setMaxShortfallRatio(ratio);

        vm.prank(curator);
        adapter.submit(abi.encodeCall(IMidnightAdapterBase.setMaxShortfallRatio, (1e18 + 1)));
        vm.expectRevert(IMidnightAdapterBase.MaxShortfallRatioTooHigh.selector);
        adapter.setMaxShortfallRatio(1e18 + 1);

        vm.prank(curator);
        adapter.submit(abi.encodeCall(IMidnightAdapterBase.setMaxShortfallRatio, (ratio)));
        vm.expectEmit(address(adapter));
        emit IMidnightAdapterBase.SetMaxShortfallRatio(ratio, 0);
        adapter.setMaxShortfallRatio(ratio);
        assertEq(adapter.maxShortfallRatio(), ratio);
    }

    function testSetShortfallRefillPeriod(uint256 period) public {
        period = bound(period, 0, type(uint40).max);
        vm.expectRevert(IMidnightAdapterBase.DataNotTimelocked.selector);
        adapter.setShortfallRefillPeriod(period);

        vm.prank(curator);
        adapter.submit(abi.encodeCall(IMidnightAdapterBase.setShortfallRefillPeriod, (period)));
        vm.expectEmit(address(adapter));
        emit IMidnightAdapterBase.SetShortfallRefillPeriod(period, 0);
        adapter.setShortfallRefillPeriod(period);
        assertEq(adapter.shortfallRefillPeriod(), period);
    }

    function testSetShortfallRefillPeriodOverflow(uint256 period) public {
        period = bound(period, uint256(type(uint40).max) + 1, type(uint256).max);
        vm.prank(curator);
        adapter.submit(abi.encodeCall(IMidnightAdapterBase.setShortfallRefillPeriod, (period)));
        vm.expectRevert(ErrorsLib.CastOverflow.selector);
        adapter.setShortfallRefillPeriod(period);
    }

    function testShortfallStoragePacking() public {
        Offer memory offer = buyMaxNetCredit();
        skip(12 hours);
        setShortfallRefillPeriod(type(uint40).max);
        setMinBuyRate(type(uint64).max);
        setUpMaxTtm(type(uint32).max);

        vm.record();
        assertEq(adapter.totalNetCredit(), type(uint128).max);
        assertEq(adapter.shortfallRefillPeriod(), type(uint40).max);
        assertEq(adapter.shortfallUpdatedAt(), vm.getBlockTimestamp());
        assertEq(adapter.maxTtm(), type(uint32).max);
        (bytes32[] memory creditReads,) = vm.accesses(address(adapter));
        assertEq(creditReads.length, 4);
        assertEq(creditReads[0], creditReads[1], "credit and refill period share one slot");
        assertEq(creditReads[0], creditReads[2], "credit and timestamp share one slot");
        assertEq(creditReads[0], creditReads[3], "credit and maxTtm share one slot");

        vm.record();
        assertEq(adapter.maxShortfallRatio(), 0.005e18);
        assertEq(adapter.shortfallAllowance(), uint256(type(uint128).max).mulDivDown(0.005e18, 1e18) / 2);
        assertEq(adapter.minBuyRate(), type(uint64).max);
        (bytes32[] memory allowanceReads,) = vm.accesses(address(adapter));
        assertEq(allowanceReads.length, 3);
        assertEq(allowanceReads[0], allowanceReads[1], "ratio and allowance share one slot");
        assertEq(allowanceReads[0], allowanceReads[2], "ratio and minBuyRate share one slot");
        assertNotEq(creditReads[0], allowanceReads[0]);

        skip(12 hours);
        adapter.withdrawToVault(offer.market, 0);
        sellUnits(offer.market, 1e18, MAX_TICK);
        assertEq(adapter.maxTtm(), type(uint32).max);
        assertEq(adapter.minBuyRate(), type(uint64).max);
    }

    function testShortfallRefillsWithLongPeriod(uint256 period) public {
        period = bound(period, uint256(type(uint24).max) + 1, type(uint40).max);
        setShortfallRefillPeriod(period);
        Offer memory offer = buy(30 days, 100e18);
        skip(period / 2);
        adapter.withdrawToVault(offer.market, 0);

        assertEq(adapter.shortfallAllowance(), uint256(0.5e18).mulDivDown(period / 2, period));
        assertEq(adapter.shortfallRefillPeriod(), period);
        assertEq(adapter.shortfallUpdatedAt(), vm.getBlockTimestamp());
        assertEq(adapter.totalNetCredit(), 100e18);
    }

    function testShortfallUpdatedAtUint48Max() public {
        Offer memory offer = buy(30 days, 100e18);
        vm.warp(type(uint48).max);
        adapter.withdrawToVault(offer.market, 0);

        assertEq(adapter.shortfallAllowance(), 0.5e18);
        assertEq(adapter.shortfallUpdatedAt(), type(uint48).max);
        assertEq(adapter.shortfallRefillPeriod(), 1 days);
        assertEq(adapter.totalNetCredit(), 100e18);
    }

    function testSetShortfallParamsChangesBothParameters(bool zeroRatio) public {
        if (zeroRatio) setShortfallParams(0, 0);
        Offer memory offer = buy(30 days, 100e18);
        skip(12 hours);

        setShortfallParams(0.01e18, 12 hours);
        uint256 allowance = zeroRatio ? 1e18 : 0.25e18;
        assertEq(adapter.shortfallAllowance(), allowance);
        assertEq(adapter.shortfallUpdatedAt(), vm.getBlockTimestamp());
        adapter.withdrawToVault(offer.market, 0);
        assertEq(adapter.shortfallAllowance(), allowance, "allowance preserved after parameter changes");

        skip(3 hours);
        adapter.withdrawToVault(offer.market, 0);
        assertEq(adapter.shortfallAllowance(), MathLib.min(1e18, allowance + 0.25e18));
    }

    function testSetShortfallParamsRefillsWithOldRatio(bool zeroRatio) public {
        if (zeroRatio) setShortfallParams(0, 1 days);
        Offer memory offer = buy(30 days, 100e18);
        setMaxSellRate(offer.market, type(uint256).max);
        skip(zeroRatio ? 1 days : 12 hours);

        setMaxShortfallRatio(0.01e18);

        uint256 allowance = zeroRatio ? 0 : 0.25e18;
        assertEq(adapter.shortfallAllowance(), allowance);
        assertEq(adapter.shortfallUpdatedAt(), vm.getBlockTimestamp());
        vm.expectRevert(IMidnightAdapterBase.MaxShortfallExceeded.selector);
        sellUnits(offer.market, 1e18, MAX_TICK / 2);
        adapter.withdrawToVault(offer.market, 0);
        assertEq(adapter.shortfallAllowance(), allowance, "no retroactive refill");

        skip(6 hours);
        adapter.withdrawToVault(offer.market, 0);
        assertEq(adapter.shortfallAllowance(), allowance + 0.25e18, "new ratio applies going forward");
    }

    function testSetMaxShortfallRatioDefersClamp(bool disable) public {
        Offer memory offer = buy(30 days, 100e18);
        skip(1 days);
        adapter.withdrawToVault(offer.market, 0);
        assertEq(adapter.shortfallAllowance(), 0.5e18);

        uint256 ratio = disable ? 0 : 0.001e18;
        vm.prank(curator);
        adapter.submit(abi.encodeCall(IMidnightAdapterBase.setMaxShortfallRatio, (ratio)));
        uint256 allowance = disable ? 0 : 0.1e18;
        vm.expectEmit(address(adapter));
        emit IMidnightAdapterBase.SetMaxShortfallRatio(ratio, 0.5e18);
        adapter.setMaxShortfallRatio(ratio);
        assertEq(adapter.shortfallAllowance(), 0.5e18, "clamp deferred until next update");

        setMaxSellRate(offer.market, type(uint256).max);
        vm.expectRevert(IMidnightAdapterBase.MaxShortfallExceeded.selector);
        sellUnits(offer.market, 2 * (allowance + 1), MAX_TICK / 2);
        adapter.withdrawToVault(offer.market, 0);
        assertEq(adapter.shortfallAllowance(), allowance);

        setShortfallParams(0.005e18, 1 days);
        adapter.withdrawToVault(offer.market, 0);
        assertEq(adapter.shortfallAllowance(), allowance, "increasing the ratio cannot restore excess allowance");
    }

    function testSetShortfallParamsClampsOldCap() public {
        Offer memory offer = buy(30 days, 100e18);
        skip(1 days);
        deal(address(loanToken), taker, 100e18);
        sellUnits(offer.market, 80e18, MAX_TICK);
        assertEq(adapter.shortfallAllowance(), 0.5e18, "stored allowance is not yet clamped");

        setMaxShortfallRatio(0.01e18);
        assertEq(adapter.shortfallAllowance(), 0.1e18, "clamp to old cap before increasing the ratio");
    }

    function testSetShortfallParamsRefillsWithOldPeriod(bool shorten) public {
        Offer memory offer = buy(30 days, 100e18);
        setMaxSellRate(offer.market, type(uint256).max);
        skip(6 hours);

        uint256 period = shorten ? 12 hours : 2 days;
        setShortfallRefillPeriod(period);

        assertEq(adapter.shortfallAllowance(), 0.125e18);
        assertEq(adapter.shortfallUpdatedAt(), vm.getBlockTimestamp());
        vm.expectRevert(IMidnightAdapterBase.MaxShortfallExceeded.selector);
        sellUnits(offer.market, 0.5e18, MAX_TICK / 2);
        adapter.withdrawToVault(offer.market, 0);
        assertEq(adapter.shortfallAllowance(), 0.125e18, "no retroactive refill");

        skip(6 hours);
        adapter.withdrawToVault(offer.market, 0);
        assertEq(adapter.shortfallAllowance(), 0.125e18 + uint256(0.5e18) * 6 hours / period);
    }

    function testSetShortfallParamsZeroPeriodTransitions(bool instantRefill) public {
        if (!instantRefill) setShortfallParams(0.005e18, 0);
        Offer memory offer = buy(30 days, 100e18);
        setMaxSellRate(offer.market, type(uint256).max);
        skip(6 hours);

        uint256 period = instantRefill ? 0 : 1 days;
        vm.prank(curator);
        adapter.submit(abi.encodeCall(IMidnightAdapterBase.setShortfallRefillPeriod, (period)));
        vm.expectEmit(address(adapter));
        emit IMidnightAdapterBase.SetShortfallRefillPeriod(period, instantRefill ? 0.125e18 : 0.5e18);
        adapter.setShortfallRefillPeriod(period);

        assertEq(adapter.shortfallAllowance(), instantRefill ? 0.125e18 : 0.5e18);
        assertEq(adapter.shortfallUpdatedAt(), vm.getBlockTimestamp());
        adapter.withdrawToVault(offer.market, 0);
        assertEq(adapter.shortfallAllowance(), 0.5e18);

        vm.expectRevert(IMidnightAdapterBase.MaxShortfallExceeded.selector);
        sellUnits(offer.market, 1e18 + 2, MAX_TICK / 2);
        sellUnits(offer.market, 1e18, MAX_TICK / 2);
        assertEq(adapter.shortfallAllowance(), 0);

        skip(6 hours);
        adapter.withdrawToVault(offer.market, 0);
        assertEq(adapter.shortfallAllowance(), instantRefill ? 0.495e18 : 0.12375e18);
    }

    function testShortfallZeroRefillPeriodEnforcesRatio(uint256 ratio, bool takerSale) public {
        ratio = bound(ratio, 0, 1e18);
        setShortfallParams(ratio, 0);
        Offer memory initial = buy(30 days, 100e18);

        vm.expectRevert(IMidnightAdapterBase.SellRateTooHigh.selector);
        sellUnits(initial.market, 40e18, MAX_TICK / 2);
        setMaxSellRate(initial.market, type(uint256).max);

        uint256 netCredit = 100e18;
        for (uint256 i; i < 2; i++) {
            Offer memory offer = takerSale
                ? makeExternalOffer(initial.market, true, 40e18, MAX_TICK / 2)
                : makeSellOffer(initial.market, 40e18, MAX_TICK / 2);
            uint256 allowance = netCredit.mulDivDown(ratio, 1e18);
            if (allowance < 20e18) {
                vm.expectRevert(IMidnightAdapterBase.MaxShortfallExceeded.selector);
            } else {
                vm.expectEmit(address(adapter));
                emit IMidnightAdapterBase.Sell(
                    _marketId(initial.market), 20e18, netCredit - 40e18, 20e18, allowance - 20e18
                );
            }
            if (takerSale) {
                vm.prank(signerAllocator);
                adapter.take(offer, "", 40e18);
            } else {
                take(offer);
            }
            if (allowance >= 20e18) {
                netCredit -= 40e18;
                assertEq(adapter.shortfallAllowance(), allowance - 20e18);
            }
            assertEq(adapter.marketData(_marketId(initial.market)).netCredit, netCredit);
        }

        setShortfallRefillPeriod(1 days);
        assertEq(adapter.shortfallAllowance(), netCredit.mulDivDown(ratio, 1e18));
        assertEq(adapter.shortfallUpdatedAt(), vm.getBlockTimestamp());
    }

    function testShortfallZeroRatioRejectsShortfallWithInstantRefill() public {
        setShortfallParams(0, 0);
        Offer memory offer = buy(30 days, 100e18);
        setMaxSellRate(offer.market, type(uint256).max);
        skip(1 days);
        vm.expectRevert(IMidnightAdapterBase.MaxShortfallExceeded.selector);
        sellUnits(offer.market, 1e18, MAX_TICK / 2);
        sellUnits(offer.market, 1e18, MAX_TICK);
        assertEq(adapter.shortfallAllowance(), 0);
    }

    function testShortfallInstantRefillClampsToStoredCredit() public {
        Offer memory offer = buy(30 days, 100e18);
        skip(1 days);
        setShortfallParams(0.005e18, 0);
        assertEq(adapter.shortfallAllowance(), 0.5e18);

        sellUnits(offer.market, 90e18, MAX_TICK);
        assertEq(adapter.shortfallAllowance(), 0.5e18);
        skip(1 days);
        adapter.withdrawToVault(offer.market, 0);
        assertEq(adapter.shortfallAllowance(), 0.05e18, "instant refill uses reduced credit");

        setShortfallParams(0.005e18, 1 days);
        assertEq(adapter.shortfallAllowance(), 0.05e18);
    }

    function testShortfallLongRefillPeriodCapsAllowance() public {
        setShortfallParams(0.005e18, type(uint24).max);
        Offer memory offer = buy(365 days, 100e18);
        skip(type(uint24).max / 2);
        adapter.withdrawToVault(offer.market, 0);
        assertEq(adapter.shortfallAllowance(), uint256(0.5e18).mulDivDown(type(uint24).max / 2, type(uint24).max));
        skip(type(uint24).max);
        adapter.withdrawToVault(offer.market, 0);
        assertEq(adapter.shortfallAllowance(), 0.5e18);
    }

    function testShortfallMaxRatio() public {
        setShortfallParams(0.1e18, 1 days);
        Offer memory offer = buy(30 days, 100e18);
        setMaxSellRate(offer.market, type(uint256).max);
        deal(address(loanToken), taker, 50e18);
        skip(1 days);
        sellUnits(offer.market, 19e18, MAX_TICK / 2);
        skip(1 days);
        vm.expectRevert(IMidnightAdapterBase.MaxShortfallExceeded.selector);
        sellUnits(offer.market, 18e18, MAX_TICK / 2);
    }

    function testShortfallRefillsLinearly(uint256 elapsed, uint256 offset) public {
        elapsed = bound(elapsed, 0, 2 days);
        offset = bound(offset, 0, 1 days - 1);
        vm.warp(10 days + offset);
        Offer memory offer = buy(30 days, 100e18);
        bytes32 marketId = _marketId(offer.market);
        assertEq(adapter.maxShortfallRatio(), 0.005e18);
        assertEq(adapter.shortfallRefillPeriod(), 1 days);
        assertEq(adapter.shortfallAllowance(), 0);
        assertEq(adapter.shortfallUpdatedAt(), vm.getBlockTimestamp());

        skip(elapsed);
        assertEq(adapter.shortfallAllowance(), 0, "stored state is not refreshed");
        adapter.withdrawToVault(offer.market, 0);
        assertEq(adapter.shortfallAllowance(), uint256(0.5e18) * MathLib.min(elapsed, 1 days) / 1 days);
        assertEq(adapter.shortfallUpdatedAt(), vm.getBlockTimestamp());
    }

    function testShortfallBeforeRefillReverts(bool takerSale) public {
        Offer memory initial = buy(30 days, 100e18);
        setMaxSellRate(initial.market, type(uint256).max);
        Offer memory offer = takerSale
            ? makeExternalOffer(initial.market, true, 1e18, MAX_TICK / 2)
            : makeSellOffer(initial.market, 1e18, MAX_TICK / 2);

        vm.expectRevert(IMidnightAdapterBase.MaxShortfallExceeded.selector);
        if (takerSale) {
            vm.prank(signerAllocator);
            adapter.take(offer, "", 1e18);
        } else {
            take(offer);
        }
        assertEq(adapter.marketData(_marketId(initial.market)).netCredit, 100e18);
    }

    function testShortfallAtLimit(bool takerSale) public {
        Offer memory initial = buy(30 days, 100e18);
        setMaxSellRate(initial.market, type(uint256).max);
        skip(1 days);
        Offer memory offer = takerSale
            ? makeExternalOffer(initial.market, true, 1e18, MAX_TICK / 2)
            : makeSellOffer(initial.market, 1e18, MAX_TICK / 2);
        deal(address(loanToken), taker, 100e18);

        if (takerSale) {
            vm.prank(signerAllocator);
            adapter.take(offer, "", 1e18);
        } else {
            take(offer);
        }
        bytes32 marketId = _marketId(initial.market);
        assertEq(adapter.shortfallAllowance(), 0);
        assertEq(adapter.marketData(marketId).netCredit, 99e18);

        vm.expectRevert(IMidnightAdapterBase.MaxShortfallExceeded.selector);
        sellUnits(initial.market, 2, MAX_TICK / 2);
        sellUnits(initial.market, 99e18, MAX_TICK);
        assertEq(adapter.marketData(marketId).netCredit, 0, "zero-shortfall exit remains possible");
        assertEq(adapter.shortfallAllowance(), 0);
    }

    function testShortfallAtLimitFromMaturity(bool takerSale, bool afterMaturity, bool zeroProceeds) public {
        Offer memory initial = buy(30 days, 100e18);
        skip(30 days + (afterMaturity ? 1 : 0));
        uint256 soldCredit = zeroProceeds ? 0.5e18 : 1e18;
        uint256 tick = zeroProceeds ? 0 : MAX_TICK / 2;
        Offer memory offer = takerSale
            ? makeExternalOffer(initial.market, true, soldCredit, MAX_TICK)
            : makeSellOffer(initial.market, soldCredit, tick);
        offer.tick = tick;
        deal(address(loanToken), taker, 100e18);
        uint256 vaultBalanceBefore = loanToken.balanceOf(address(parentVault));

        if (takerSale) {
            vm.prank(signerAllocator);
            adapter.take(offer, "", soldCredit);
        } else {
            take(offer);
        }
        bytes32 marketId = _marketId(initial.market);
        assertEq(adapter.shortfallAllowance(), 0, "shortfall charged from maturity");
        assertEq(adapter.marketData(marketId).netCredit, 100e18 - soldCredit);
        assertEq(
            loanToken.balanceOf(address(parentVault)), vaultBalanceBefore + (zeroProceeds ? 0 : 0.5e18), "sale proceeds"
        );

        vm.expectRevert(IMidnightAdapterBase.MaxShortfallExceeded.selector);
        sellUnits(initial.market, 2, tick);
        sellUnits(initial.market, 100e18 - soldCredit, MAX_TICK);
        assertEq(adapter.marketData(marketId).netCredit, 0, "zero-shortfall exit remains possible");
        assertEq(adapter.shortfallAllowance(), 0);
    }

    function testShortfallLimitFuzz(uint256 position, uint256 elapsed) public {
        position = bound(position, 2, MAX_TEST_ASSETS);
        elapsed = bound(elapsed, 0, 2 days);
        Offer memory offer = buy(30 days, position);
        setMaxSellRate(offer.market, type(uint256).max);
        skip(elapsed);
        uint256 limit = position.mulDivDown(adapter.maxShortfallRatio(), 1e18);
        limit = limit.mulDivDown(MathLib.min(elapsed, 1 days), 1 days);

        vm.expectRevert(IMidnightAdapterBase.MaxShortfallExceeded.selector);
        sellUnits(offer.market, 2 * (limit + 1), MAX_TICK / 2);
        if (limit > 0) sellAndRebuyWithShortfall(offer.market, limit);

        assertEq(adapter.shortfallAllowance(), 0);
        assertEq(adapter.marketData(_marketId(offer.market)).netCredit, position - limit);
    }

    function testShortfallMaxNetCredit() public {
        Offer memory offer = buyMaxNetCredit();
        setMaxSellRate(offer.market, type(uint256).max);
        skip(1 days);
        uint256 limit = uint256(type(uint128).max).mulDivDown(adapter.maxShortfallRatio(), 1e18);
        sellAndRebuyWithShortfall(offer.market, limit);
        assertEq(adapter.shortfallAllowance(), 0);
        assertEq(adapter.marketData(_marketId(offer.market)).netCredit, type(uint128).max - limit);
    }

    /// forge-config: default.isolate = true
    function testShortfallLargePositionRemainsUsable(uint256 action) public {
        action = bound(action, 0, 5);
        setUpRealVault();
        setShortfallParams(0.1e18, 1 days);
        uint256 assets = 10 * (uint256(type(uint112).max) + 1);
        deal(address(loanToken), address(this), assets);
        realVault.deposit(assets, address(this));
        deal(storedCollaterals[0].token, address(this), assets);
        deal(storedCollaterals[1].token, address(this), assets);
        Offer memory offer = buyOnRealVault(30 days, assets);
        assertEq(realVault.allocation(adapter.adapterId()), assets);
        skip(1 days);

        uint256 expectedNetCredit = assets;
        if (action == 0) {
            buyOnRealVault(29 days, 1e18);
            expectedNetCredit += 1e18;
        } else if (action == 1) {
            sellUnits(offer.market, assets / 2, MAX_TICK);
            expectedNetCredit -= assets / 2;
        } else if (action == 2) {
            vm.prank(taker);
            midnight.repay(offer.market, assets / 2, taker, address(0), "");
            adapter.withdrawToVault(offer.market, assets / 2);
            expectedNetCredit -= assets / 2;
        } else if (action == 3) {
            forceDeallocateOnRealVault(offer.market, assets / 2);
            expectedNetCredit -= assets / 2;
        } else if (action == 4) {
            setShortfallParams(0, 1 days);
            assertEq(adapter.maxShortfallRatio(), 0);
        } else {
            setShortfallParams(0.1e18, 0);
            assertEq(adapter.shortfallRefillPeriod(), 0);
        }
        assertEq(adapter.shortfallAllowance(), action == 4 ? 0 : assets / 10);
        assertEq(adapter.shortfallUpdatedAt(), vm.getBlockTimestamp());
        assertEq(adapter.totalNetCredit(), expectedNetCredit);
        assertEq(realVault.allocation(adapter.adapterId()), expectedNetCredit);
    }

    function testShortfallAccumulatesAcrossSales() public {
        Offer memory offer = buy(30 days, 100e18);
        setMaxSellRate(offer.market, type(uint256).max);
        skip(1 days);
        deal(address(loanToken), taker, 100e18);
        sellUnits(offer.market, 0.5e18, MAX_TICK / 2);
        assertEq(adapter.shortfallAllowance(), 0.25e18);

        vm.expectRevert(IMidnightAdapterBase.MaxShortfallExceeded.selector);
        sellUnits(offer.market, 0.5e18 + 2, MAX_TICK / 2);
        sellUnits(offer.market, 0.5e18, MAX_TICK / 2);
        assertEq(adapter.shortfallAllowance(), 0);
        assertEq(adapter.marketData(_marketId(offer.market)).netCredit, 99e18);
    }

    function testShortfallNoMidnightReset() public {
        vm.warp(1);
        Offer memory offer = buy(30 days, 100e18);
        setMaxSellRate(offer.market, type(uint256).max);
        vm.warp(2 days - 1);
        sellAndRebuyWithShortfall(offer.market, 0.5e18);

        vm.warp(2 days);
        uint256 refill = uint256(0.4975e18) / 1 days;
        vm.expectRevert(IMidnightAdapterBase.MaxShortfallExceeded.selector);
        sellUnits(offer.market, 2 * (refill + 1), MAX_TICK / 2);
        sellAndRebuyWithShortfall(offer.market, refill);
        assertEq(adapter.shortfallAllowance(), 0);
    }

    function testShortfallRefillAfterPartialSpend() public {
        Offer memory offer = buy(30 days, 100e18);
        setMaxSellRate(offer.market, type(uint256).max);
        skip(1 days);
        sellAndRebuyWithShortfall(offer.market, 0.25e18);
        bytes32 marketId = _marketId(offer.market);
        assertEq(adapter.shortfallAllowance(), 0.25e18);

        skip(6 hours);
        adapter.withdrawToVault(offer.market, 0);
        assertEq(adapter.shortfallAllowance(), 0.25e18 + 0.49875e18 / 4);
        skip(6 hours);
        adapter.withdrawToVault(offer.market, 0);
        assertEq(adapter.shortfallAllowance(), 0.49875e18, "refill uses full cap, not missing allowance");
    }

    function testShortfallDoesNotBankUnusedDays(uint256 elapsed) public {
        elapsed = bound(elapsed, 1 days, 18249 days);
        Offer memory offer = buy(2 * elapsed + 1 days, 100e18);
        setMaxSellRate(offer.market, type(uint256).max);
        skip(elapsed);

        vm.expectRevert(IMidnightAdapterBase.MaxShortfallExceeded.selector);
        sellUnits(offer.market, 2 * (0.5e18 + 1), MAX_TICK / 2);
        sellAndRebuyWithShortfall(offer.market, 0.5e18);
        skip(elapsed);
        sellAndRebuyWithShortfall(offer.market, 0.4975e18);
        assertEq(adapter.shortfallAllowance(), 0);
    }

    function testShortfallBuyOnlyIncreasesFutureRefill() public {
        Offer memory offer = buy(30 days, 100e18);
        skip(12 hours);
        Offer memory additionalOffer = makeBuyOffer(offer.market.maturity - block.timestamp, 900e18, MAX_TICK);
        additionalOffer.group = bytes32(vm.randomUint());
        midnight.supplyCollateral(offer.market, 0, 900e18, taker);
        midnight.supplyCollateral(offer.market, 1, 900e18, taker);
        vm.expectEmit(address(adapter));
        emit IMidnightAdapterBase.Buy(_marketId(offer.market), 900e18, 900e18, 1000e18, 0.25e18);
        take(additionalOffer);
        bytes32 marketId = _marketId(offer.market);
        assertEq(adapter.shortfallAllowance(), 0.25e18, "elapsed time uses old credit");

        skip(1 hours);
        adapter.withdrawToVault(offer.market, 0);
        assertEq(adapter.shortfallAllowance(), 0.25e18 + uint256(5e18) / 24);
    }

    function testShortfallRefillUsesStoredCredit(uint256 credit) public {
        credit = bound(credit, 1, 100e18);
        Offer memory offer = buy(30 days, 100e18);
        skip(12 hours);
        setMidnightCredit(_marketId(offer.market), address(adapter), credit);

        adapter.withdrawToVault(offer.market, 0);
        uint256 limit = uint256(100e18).mulDivDown(adapter.maxShortfallRatio(), 1e18);
        assertEq(adapter.shortfallAllowance(), limit / 2);
        assertEq(adapter.totalNetCredit(), credit);

        skip(12 hours);
        adapter.withdrawToVault(offer.market, 0);
        uint256 newLimit = credit.mulDivDown(adapter.maxShortfallRatio(), 1e18);
        assertEq(adapter.shortfallAllowance(), MathLib.min(newLimit, limit / 2 + newLimit / 2));
    }

    function testShortfallSameBlockCreditCannotInflateAllowance() public {
        Offer memory offer = buy(30 days, 100e18);
        setMaxSellRate(offer.market, type(uint256).max);
        skip(12 hours);
        buyAdditionalCredit(offer.market, 900e18);
        bytes32 marketId = _marketId(offer.market);

        vm.expectRevert(IMidnightAdapterBase.MaxShortfallExceeded.selector);
        sellUnits(offer.market, 2 * (0.25e18 + 1), MAX_TICK / 2);
        deal(address(loanToken), taker, 900e18);
        sellUnits(offer.market, 900e18, MAX_TICK);
        assertEq(adapter.shortfallAllowance(), 0.25e18);

        skip(12 hours);
        adapter.withdrawToVault(offer.market, 0);
        assertEq(adapter.shortfallAllowance(), 0.5e18);
    }

    function testShortfallSaleClampsAllowance() public {
        Offer memory offer = buy(30 days, 100e18);
        setMaxSellRate(offer.market, type(uint256).max);
        skip(12 hours);
        deal(address(loanToken), taker, 100e18);
        sellUnits(offer.market, 10e18, MAX_TICK);
        assertEq(adapter.shortfallAllowance(), 0.25e18, "refill precedes reduction");

        sellUnits(offer.market, 80e18, MAX_TICK);
        assertEq(adapter.shortfallAllowance(), 0.25e18, "stored allowance is not yet clamped");
        vm.expectRevert(IMidnightAdapterBase.MaxShortfallExceeded.selector);
        sellUnits(offer.market, 2 * (0.05e18 + 1), MAX_TICK / 2);
        skip(6 hours);
        vm.expectRevert(IMidnightAdapterBase.MaxShortfallExceeded.selector);
        sellUnits(offer.market, 2 * (0.05e18 + 1), MAX_TICK / 2);
        sellAndRebuyWithShortfall(offer.market, 0.05e18);
        assertEq(adapter.shortfallAllowance(), 0);
    }

    function testShortfallWithdrawalClampsAllowance() public {
        Offer memory offer = buy(30 days, 100e18);
        setMaxSellRate(offer.market, type(uint256).max);
        skip(12 hours);
        deal(address(loanToken), address(this), 90e18);
        loanToken.approve(address(midnight), 90e18);
        midnight.repay(offer.market, 90e18, taker, address(0), "");

        adapter.withdrawToVault(offer.market, 10e18);
        assertEq(adapter.shortfallAllowance(), 0.25e18, "refill precedes withdrawal");
        adapter.withdrawToVault(offer.market, 80e18);
        assertEq(adapter.shortfallAllowance(), 0.25e18, "stored allowance is not yet clamped");
        vm.expectRevert(IMidnightAdapterBase.MaxShortfallExceeded.selector);
        sellUnits(offer.market, 2 * (0.05e18 + 1), MAX_TICK / 2);
        sellAndRebuyWithShortfall(offer.market, 0.05e18);
        assertEq(adapter.shortfallAllowance(), 0);
    }

    function testShortfallForceDeallocateClampsAllowance() public {
        Offer memory initial = buy(30 days, 100e18);
        setMaxSellRate(initial.market, type(uint256).max);
        skip(12 hours);
        forceDeallocate(initial.market, 10e18);
        assertEq(adapter.shortfallAllowance(), 0.25e18);
        forceDeallocate(initial.market, 80e18);
        assertEq(adapter.shortfallAllowance(), 0.25e18);
        vm.expectRevert(IMidnightAdapterBase.MaxShortfallExceeded.selector);
        sellUnits(initial.market, 2 * (0.05e18 + 1), MAX_TICK / 2);
        sellAndRebuyWithShortfall(initial.market, 0.05e18);
        assertEq(adapter.shortfallAllowance(), 0);
    }

    function testShortfallBuyCannotRestoreUnclampedAllowance() public {
        Offer memory offer = buy(30 days, 100e18);
        setMaxSellRate(offer.market, type(uint256).max);
        skip(12 hours);
        deal(address(loanToken), taker, 100e18);
        sellUnits(offer.market, 90e18, MAX_TICK);
        assertEq(adapter.shortfallAllowance(), 0.25e18);

        buyAdditionalCredit(offer.market, 90e18);
        assertEq(adapter.shortfallAllowance(), 0.05e18, "clamp uses pre-purchase credit");
        vm.expectRevert(IMidnightAdapterBase.MaxShortfallExceeded.selector);
        sellUnits(offer.market, 2 * (0.05e18 + 1), MAX_TICK / 2);
        sellAndRebuyWithShortfall(offer.market, 0.05e18);
        assertEq(adapter.shortfallAllowance(), 0);
    }

    function testShortfallBuyAfterDefaultUsesStoredCredit(bool fullAllowance) public {
        Offer memory offer = buy(30 days, 100e18);
        skip(fullAllowance ? 1 days : 12 hours);
        if (fullAllowance) adapter.withdrawToVault(offer.market, 0);
        this.realizeDefault(offer.market, ORACLE_PRICE_SCALE / 4);
        uint256 remaining = adapter.realAssets();
        assertLt(remaining, 100e18);
        assertGt(remaining, 0);
        OracleMock(storedCollaterals[0].oracle).setPrice(ORACLE_PRICE_SCALE);
        OracleMock(storedCollaterals[1].oracle).setPrice(ORACLE_PRICE_SCALE);

        buyAdditionalCredit(offer.market, 100e18 - remaining);
        uint256 limit = uint256(100e18).mulDivDown(adapter.maxShortfallRatio(), 1e18);
        assertEq(adapter.shortfallAllowance(), fullAllowance ? limit : limit / 2);
        assertEq(adapter.marketData(_marketId(offer.market)).netCredit, 100e18);
    }

    function testShortfallSaleAfterDefaultUsesStoredCredit() public {
        Offer memory offer = buy(30 days, 100e18);
        setMaxSellRate(offer.market, type(uint256).max);
        skip(1 days);
        adapter.withdrawToVault(offer.market, 0);
        this.realizeDefault(offer.market, ORACLE_PRICE_SCALE / 4);
        uint256 remaining = adapter.realAssets();
        uint256 limit = uint256(100e18).mulDivDown(adapter.maxShortfallRatio(), 1e18);

        vm.expectRevert(IMidnightAdapterBase.MaxShortfallExceeded.selector);
        sellUnits(offer.market, 2 * (limit + 1), MAX_TICK / 2);
        sellUnits(offer.market, 2 * limit, MAX_TICK / 2);
        assertEq(adapter.marketData(_marketId(offer.market)).netCredit, remaining - 2 * limit);
        assertEq(adapter.shortfallAllowance(), 0);

        adapter.withdrawToVault(offer.market, 0);
        skip(1 days);
        adapter.withdrawToVault(offer.market, 0);
        assertEq(adapter.shortfallAllowance(), (remaining - 2 * limit).mulDivDown(adapter.maxShortfallRatio(), 1e18));
    }

    function testShortfallFullExitAndReentryStartsEmpty() public {
        Offer memory offer = buy(30 days, 100e18);
        setMaxSellRate(offer.market, type(uint256).max);
        skip(1 days);
        sellAndRebuyWithShortfall(offer.market, 0.1e18);
        assertEq(adapter.shortfallAllowance(), 0.4e18);
        deal(address(loanToken), taker, 100e18);
        sellUnits(offer.market, 99.9e18, MAX_TICK);
        assertEq(adapter.marketIdsLength(), 0);
        assertEq(adapter.shortfallAllowance(), 0.4e18, "stored allowance survives exit");

        skip(1 days);
        buyAdditionalCredit(offer.market, 100e18);
        assertEq(adapter.shortfallAllowance(), 0);
        vm.expectRevert(IMidnightAdapterBase.MaxShortfallExceeded.selector);
        sellUnits(offer.market, 2, MAX_TICK / 2);
    }

    function testShortfallIsGlobal() public {
        Offer memory first = buy(30 days, 100e18);
        setMaxSellRate(first.market, type(uint256).max);
        Offer memory second = buy(31 days, 100e18);
        skip(12 hours);
        adapter.withdrawToVault(first.market, 0);
        assertEq(adapter.shortfallAllowance(), 0.5e18, "refill uses total net credit");
        skip(12 hours);
        sellAndRebuyWithShortfall(first.market, 1e18);
        assertEq(adapter.shortfallAllowance(), 0);
        vm.expectRevert(IMidnightAdapterBase.MaxShortfallExceeded.selector);
        sellUnits(second.market, 2, MAX_TICK / 2);
    }

    function testShortfallNewMarketSpendsSharedAllowance() public {
        Offer memory first = buy(30 days, 100e18);
        setMaxSellRate(first.market, type(uint256).max);
        skip(1 days);
        Offer memory second = buy(31 days, 100e18);
        assertEq(adapter.shortfallAllowance(), 0.5e18, "purchase does not add allowance");
        sellAndRebuyWithShortfall(second.market, 0.5e18);
        assertEq(adapter.shortfallAllowance(), 0);
    }

    function testShortfallSelfFundedRollKeepsAllowance() public {
        Offer memory offer = buy(30 days, 100e18);
        skip(1 days);
        deal(address(loanToken), address(this), 50e18);
        loanToken.approve(address(midnight), 50e18);
        midnight.repay(offer.market, 50e18, taker, address(0), "");
        deal(address(loanToken), address(parentVault), 0);

        Offer memory roll = makeBuyOffer(31 days, 50e18, MAX_TICK);
        roll.callbackData = abi.encode(address(adapter), abi.encode(offer.market));
        midnight.supplyCollateral(roll.market, 0, roll.maxUnits, taker);
        midnight.supplyCollateral(roll.market, 1, roll.maxUnits, taker);
        vm.expectEmit(address(adapter));
        emit IMidnightAdapterBase.WithdrawToVault(_marketId(offer.market), 50e18, 50e18, 0.5e18);
        vm.expectEmit(address(adapter));
        emit IMidnightAdapterBase.Buy(_marketId(roll.market), 50e18, 50e18, 50e18, 0.5e18);
        take(roll);
        assertEq(adapter.shortfallAllowance(), 0.5e18, "shortfallAllowance");

        assertEq(adapter.marketData(_marketId(offer.market)).netCredit, 50e18);
        assertEq(adapter.marketData(_marketId(roll.market)).netCredit, 50e18);
        assertEq(adapter.shortfallAllowance(), 0.5e18, "purchase counted before the withdrawal");
    }

    function testBuySelfFundedSameMarketEmitsFinalNetCredit() public {
        Offer memory initial = buy(30 days, 100e18);
        bytes32 marketId = _marketId(initial.market);
        skip(1 days);
        deal(address(loanToken), address(this), 50e18);
        loanToken.approve(address(midnight), 50e18);
        midnight.repay(initial.market, 50e18, taker, address(0), "");
        deal(address(loanToken), address(parentVault), 0);

        Offer memory roll = makeBuyOffer(initial.market.maturity - block.timestamp, 50e18, MAX_TICK);
        roll.market = initial.market;
        roll.group = bytes32(vm.randomUint());
        roll.callbackData = abi.encode(address(adapter), abi.encode(initial.market));
        midnight.supplyCollateral(roll.market, 0, roll.maxUnits, taker);
        midnight.supplyCollateral(roll.market, 1, roll.maxUnits, taker);
        vm.expectEmit(address(adapter));
        emit IMidnightAdapterBase.WithdrawToVault(marketId, 50e18, 100e18, 0.5e18);
        vm.expectEmit(address(adapter));
        emit IMidnightAdapterBase.Buy(marketId, 50e18, 50e18, 100e18, 0.5e18);
        take(roll);

        assertEq(adapter.marketData(marketId).netCredit, 100e18);
        assertEq(adapter.shortfallAllowance(), 0.5e18);
    }

    function testShortfallExitClampsSharedAllowance() public {
        Offer memory first = buy(30 days, 100e18);
        setMaxSellRate(first.market, type(uint256).max);
        Offer memory second = buy(31 days, 100e18);
        skip(1 days);
        deal(address(loanToken), taker, 101e18);
        sellUnits(second.market, 100e18, MAX_TICK);
        assertEq(adapter.shortfallAllowance(), 1e18, "stored allowance is not yet clamped");
        vm.expectRevert(IMidnightAdapterBase.MaxShortfallExceeded.selector);
        sellUnits(first.market, 2 * (0.5e18 + 1), MAX_TICK / 2);
        sellAndRebuyWithShortfall(first.market, 0.5e18);
        assertEq(adapter.shortfallAllowance(), 0);
    }

    function testShortfallProfitsDoNotRefillAllowance() public {
        Offer memory offer = buy(30 days, 100e18, MAX_TICK / 2);
        setMaxSellRate(offer.market, type(uint256).max);
        skip(12 hours);
        deal(address(loanToken), taker, 1e18);
        sellUnits(offer.market, 1e18, MAX_TICK);
        assertEq(adapter.shortfallAllowance(), 0.5e18);
    }

    function testFullSaleUsesGrowthBeforeClearingMarketData() public {
        setShortfallParams(1e18, 0);
        Offer memory offer = buy(30 days, 100e18, MAX_TICK / 2);
        setMaxSellRate(offer.market, type(uint256).max);
        skip(1 days);
        deal(address(loanToken), taker, 100e18);
        uint256 expectedShortfall = adapter.realAssets() - 100e18;
        assertGt(adapter.marketData(_marketId(offer.market)).growth, 0);

        vm.expectEmit(address(adapter));
        emit IMidnightAdapterBase.Sell(
            _marketId(offer.market), 100e18, 0, expectedShortfall, 200e18 - expectedShortfall
        );
        sellUnits(offer.market, 200e18, MAX_TICK / 2);

        assertEq(adapter.shortfallAllowance(), 200e18 - expectedShortfall);
        assertEq(adapter.marketIdsLength(), 0);
        assertEq(abi.encode(adapter.marketData(_marketId(offer.market))), abi.encode(MarketData(0, 0, 0, 0, 0, 0)));
    }

    function testShortfallUsesAmortizedValue() public {
        Offer memory offer = buy(30 days, 100e18, MAX_TICK / 2);
        setMaxSellRate(offer.market, type(uint256).max);
        skip(1 days);
        deal(address(loanToken), taker, 1e18);
        uint256 growth = uint64(uint256(100e18).mulDivDown(1e18, 30 days) / 200e18);
        uint256 discountFactor = 1e18 - growth * (offer.market.maturity - vm.getBlockTimestamp());
        uint256 saleShortfall = (uint256(200e18).mulDivDown(discountFactor, 1e18)
                - uint256(198e18).mulDivDown(discountFactor, 1e18))
        .zeroFloorSub(1e18);
        uint256 assetsBefore = adapter.realAssets();
        vm.expectEmit(address(adapter));
        emit IMidnightAdapterBase.Sell(_marketId(offer.market), 1e18, 198e18, saleShortfall, 1e18 - saleShortfall);
        sellUnits(offer.market, 2e18, MAX_TICK / 2);
        assertEq(saleShortfall, (assetsBefore - adapter.realAssets()).zeroFloorSub(1e18), "book value decrease");
        assertEq(adapter.shortfallAllowance(), 1e18 - saleShortfall);
    }

    function testShortfallEqualsBookValueDecrease(uint256 elapsed, uint256 sold, uint256 sellPrice) public {
        Offer memory offer = buy(30 days, 100e18, discountTick);
        setMaxSellRate(offer.market, type(uint256).max);
        skip(bound(elapsed, 1 days, 30 days - 1));
        bytes32 marketId = _marketId(offer.market);
        sold = bound(
            sold, 1, uint256(adapter.marketData(marketId).netCredit).mulDivDown(adapter.maxShortfallRatio(), 1e18)
        );
        uint256 tick = TickLib.priceToTick(bound(sellPrice, 0.5e18, 1e18), DEFAULT_TICK_SPACING);
        deal(address(loanToken), taker, 100e18);

        // Refill the allowance at this timestamp so the sale's only allowance change is its shortfall.
        adapter.withdrawToVault(offer.market, 0);
        uint256 allowanceBefore = adapter.shortfallAllowance();
        uint256 assetsBefore = adapter.realAssets();
        uint256 balanceBefore = loanToken.balanceOf(address(parentVault));

        sellUnits(offer.market, sold, tick);

        uint256 proceeds = loanToken.balanceOf(address(parentVault)) - balanceBefore;
        uint256 bookShortfall = (assetsBefore - adapter.realAssets()).zeroFloorSub(proceeds);
        assertEq(allowanceBefore - adapter.shortfallAllowance(), bookShortfall, "charged the book value decrease");
    }

    function testShortfallRefillUsesNetCredit() public {
        midnight.setDefaultContinuousFee(address(loanToken), MAX_CONTINUOUS_FEE);
        Offer memory offer = buy(30 days, 100e18, discountTick);
        bytes32 marketId = _marketId(offer.market);
        uint256 credit = adapter.marketData(marketId).netCredit;
        assertLt(credit, midnight.credit(marketId, address(adapter)));

        skip(12 hours);
        adapter.withdrawToVault(offer.market, 0);
        assertEq(adapter.marketData(marketId).netCredit, credit, "continuous fee accrual preserves net credit");
        assertEq(adapter.shortfallAllowance(), credit.mulDivDown(adapter.maxShortfallRatio(), 1e18) / 2);
    }

    function testShortfallDailyBound(uint256 seed) public {
        Offer memory offer = buy(30 days, 100e18);
        setMaxSellRate(offer.market, type(uint256).max);
        skip(1 days);
        uint256 start = vm.getBlockTimestamp();
        uint256 totalShortfall;
        for (uint256 i; i < 7; i++) {
            if (i > 0) {
                seed = uint256(keccak256(abi.encode(seed, i)));
                skip(seed % (4 hours + 1));
            }
            adapter.withdrawToVault(offer.market, 0);
            uint256 saleShortfall = adapter.shortfallAllowance();
            if (saleShortfall > 0) {
                sellAndRebuyWithShortfall(offer.market, saleShortfall);
                buyAdditionalCredit(offer.market, saleShortfall);
                totalShortfall += saleShortfall;
            }
            assertEq(adapter.marketData(_marketId(offer.market)).netCredit, 100e18);
            assertEq(adapter.shortfallAllowance(), 0);
            assertLe(totalShortfall, 0.5e18 + uint256(0.5e18) * (vm.getBlockTimestamp() - start) / 1 days);
        }
        assertLe(totalShortfall, 1e18);
    }

    function testShortfallOperationEvents() public {
        Offer memory offer = makeBuyOffer(30 days, 100e18, MAX_TICK);
        midnight.supplyCollateral(offer.market, 0, offer.maxUnits, taker);
        midnight.supplyCollateral(offer.market, 1, offer.maxUnits, taker);
        vm.expectEmit(address(adapter));
        emit IMidnightAdapterBase.Buy(_marketId(offer.market), 100e18, 100e18, 100e18, 0);
        take(offer);
        setMaxSellRate(offer.market, type(uint256).max);

        skip(12 hours);
        vm.expectEmit(address(adapter));
        emit IMidnightAdapterBase.WithdrawToVault(_marketId(offer.market), 0, 100e18, 0.25e18);
        adapter.withdrawToVault(offer.market, 0);

        vm.expectEmit(address(adapter));
        emit IMidnightAdapterBase.Sell(_marketId(offer.market), 90e18, 10e18, 0, 0.25e18);
        sellUnits(offer.market, 90e18, MAX_TICK);

        vm.expectEmit(address(adapter));
        emit IMidnightAdapterBase.Sell(_marketId(offer.market), 0.01e18, 9.98e18, 0.01e18, 0.04e18);
        sellUnits(offer.market, 0.02e18, MAX_TICK / 2);
        assertEq(adapter.shortfallAllowance(), 0.04e18);
    }

    /* HELPERS */

    /// @dev Computes expected claim value from native credit and the adapter's ownership balances.
    function claimAssets(Market memory market, uint256 shares) internal view returns (uint256) {
        bytes32 id = _marketId(market);
        uint256 total = adapter.marketData(id).totalShares;
        (uint128 credit,,) = midnight.updatePositionView(market, id, address(adapter));
        return total == 0 ? 0 : uint256(credit) * shares / total;
    }

    function sellAndRebuyWithShortfall(Market memory market, uint256 shortfall) internal {
        sellUnits(market, 2 * shortfall, MAX_TICK / 2);
        Offer memory rebuy = makeBuyOffer(market.maturity - block.timestamp, shortfall, MAX_TICK);
        rebuy.market = market;
        rebuy.group = bytes32(vm.randomUint());
        take(rebuy);
    }

    function buyAdditionalCredit(Market memory market, uint256 assets) internal {
        Offer memory offer = makeBuyOffer(market.maturity - block.timestamp, assets, MAX_TICK);
        offer.group = bytes32(vm.randomUint());
        midnight.supplyCollateral(market, 0, assets, taker);
        midnight.supplyCollateral(market, 1, assets, taker);
        take(offer);
    }

    function durationIdData(IMidnightAdapter target, uint256 duration) internal pure returns (bytes memory) {
        return abi.encode("duration", address(target), duration);
    }

    function disableDurationCaps(IMidnightAdapter target) internal {
        IVaultV2 vault = IVaultV2(target.parentVault());
        for (uint256 i; i < allDurations.length; i++) {
            bytes memory idData = durationIdData(target, allDurations[i]);
            if (address(vault) == address(realVault)) {
                submitAndCall(vault, abi.encodeCall(IVaultV2.increaseRelativeCap, (idData, 1e18)));
                submitAndCall(vault, abi.encodeCall(IVaultV2.increaseAbsoluteCap, (idData, type(uint128).max)));
            } else {
                VaultV2Mock(address(vault)).setRelativeCap(keccak256(idData), 1e18);
                VaultV2Mock(address(vault)).setAbsoluteCap(keccak256(idData), type(uint128).max);
            }
        }
    }

    function decreaseDurationCap(uint256 index, uint256 cap) internal {
        bytes memory idData = durationIdData(adapter, allDurations[index]);
        if (adapter.parentVault() == address(realVault)) {
            vm.prank(curator);
            realVault.decreaseRelativeCap(idData, cap);
        } else {
            VaultV2Mock(adapter.parentVault()).setRelativeCap(keccak256(idData), cap);
        }
    }

    function decreaseDurationAbsoluteCap(uint256 index, uint256 cap) internal {
        bytes memory idData = durationIdData(adapter, allDurations[index]);
        if (adapter.parentVault() == address(realVault)) {
            vm.prank(curator);
            realVault.decreaseAbsoluteCap(idData, cap);
        } else {
            VaultV2Mock(adapter.parentVault()).setAbsoluteCap(keccak256(idData), cap);
        }
    }

    function setUpMaxTtm(uint256 maxTtm) internal {
        vm.prank(curator);
        adapter.submit(abi.encodeCall(IMidnightAdapterBase.setMaxTtm, (maxTtm)));
        adapter.setMaxTtm(maxTtm);
    }

    function makeBuyOffer(uint256 duration, uint256 assets, uint256 tick) internal view returns (Offer memory offer) {
        offer = storedOffer;
        offer.market.maturity = block.timestamp + duration;
        offer.buy = true;
        offer.tick = tick;
        offer.group = bytes32(duration);
        offer.maxUnits = uint128(assets * 1e18 / TickLib.tickToPrice(tick));
        offer.expiry = block.timestamp;
        offer.callback = address(adapter);
        offer.callbackData = hex"";
    }

    function setSkimRecipient(address newSkimRecipient) internal {
        vm.prank(curator);
        adapter.submit(abi.encodeCall(IMidnightAdapterBase.setSkimRecipient, (newSkimRecipient)));
        vm.expectEmit(true, false, false, false, address(adapter));
        emit IMidnightAdapterBase.SetSkimRecipient(newSkimRecipient);
        adapter.setSkimRecipient(newSkimRecipient);
    }

    function setShortfallParams(uint256 ratio, uint256 period) internal {
        setMaxShortfallRatio(ratio);
        setShortfallRefillPeriod(period);
    }

    function setMaxShortfallRatio(uint256 ratio) internal {
        vm.prank(curator);
        adapter.submit(abi.encodeCall(IMidnightAdapterBase.setMaxShortfallRatio, (ratio)));
        adapter.setMaxShortfallRatio(ratio);
    }

    function setShortfallRefillPeriod(uint256 period) internal {
        vm.prank(curator);
        adapter.submit(abi.encodeCall(IMidnightAdapterBase.setShortfallRefillPeriod, (period)));
        adapter.setShortfallRefillPeriod(period);
    }

    function submitTimelock(bytes4 selector, uint256 duration) internal {
        vm.prank(curator);
        adapter.submit(abi.encodeCall(IMidnightAdapterBase.increaseTimelock, (selector, duration)));
        adapter.increaseTimelock(selector, duration);
    }

    function addSubRatifier(IMidnightAdapter _adapter, address subRatifier) internal {
        vm.prank(signerAllocator);
        _adapter.setIsSubRatifier(subRatifier, true);
    }

    function setMaxSellRate(Market memory market, uint256 newMaxSellRate) internal {
        bytes32 collateralParamsHash = keccak256(abi.encode(market.collateralParams));
        vm.prank(curator);
        adapter.setMaxSellRate(collateralParamsHash, newMaxSellRate);
    }

    function setMinBuyRate(uint256 newMinBuyRate) internal {
        vm.prank(curator);
        adapter.setMinBuyRate(newMinBuyRate);
    }

    function take(Offer memory offer) internal {
        this.takeWithAccrual(offer, "", taker, address(0));
    }

    /// @dev Keeps accrual and take in one transaction when tests run with isolation.
    function takeWithAccrual(Offer memory offer, bytes memory data, address account, address callback) external {
        if (data.length == 0) data = ratify([offer], signerAllocator);
        IVaultV2(IMidnightAdapter(offer.maker).parentVault()).accrueInterest();
        vm.prank(account);
        midnight.take(offer, data, offer.maxUnits, account, offer.buy ? account : address(0), callback, "");
    }

    function buy(uint256 duration, uint256 assets) internal returns (Offer memory) {
        return buy(duration, assets, MAX_TICK);
    }

    function buy(uint256 duration, uint256 assets, uint256 tick) internal returns (Offer memory offer) {
        offer = makeBuyOffer(duration, assets, tick);
        midnight.supplyCollateral(offer.market, 0, offer.maxUnits, taker);
        midnight.supplyCollateral(offer.market, 1, offer.maxUnits, taker);
        take(offer);
    }

    function buyMaxNetCredit() internal returns (Offer memory) {
        uint256 assets = type(uint128).max;
        deal(address(loanToken), address(parentVault), assets);
        deal(storedCollaterals[0].token, address(this), assets);
        deal(storedCollaterals[1].token, address(this), assets);
        return buy(7 days, assets);
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
        offer.maxUnits = uint128(units);
        offer.expiry = block.timestamp;
        offer.maker = address(adapter);
        offer.callback = address(adapter);
        offer.ratifier = address(adapter);
        offer.receiverIfMakerIsSeller = address(adapter);
        offer.group = bytes32(vm.randomUint());
        offer.callbackData = hex"";
    }

    function sell(Market memory market, uint256 assets) internal {
        Offer memory offer = makeSellOffer(market, 0, MAX_TICK);
        offer.maxUnits =
            uint128(TakeAmountsLib.sellerAssetsToUnits(address(midnight), _marketId(market), offer, assets));
        this.takeWithAccrual(offer, "", taker, address(0));
    }

    function sellUnits(Market memory market, uint256 units, uint256 tick) internal {
        Offer memory offer = makeSellOffer(market, units, tick);
        this.takeWithAccrual(offer, "", taker, address(0));
    }

    /// @dev Builds an external offer at `tick`, ratified by this contract. Buy offers get a funded maker, sell offers get a collateralized one.
    function makeExternalOffer(Market memory market, bool isBuy, uint256 assets, uint256 tick)
        internal
        returns (Offer memory offer)
    {
        address maker = makeAddr(isBuy ? "externalBuyer" : "externalSeller");
        vm.prank(maker);
        midnight.setIsAuthorized(address(this), true, maker);

        offer = storedOffer;
        offer.market = market;
        offer.buy = isBuy;
        offer.maker = maker;
        offer.tick = tick;
        offer.maxUnits = uint128(assets * 1e18 / TickLib.tickToPrice(tick));
        offer.expiry = block.timestamp;
        offer.callback = address(0);
        offer.receiverIfMakerIsSeller = isBuy ? address(0) : maker;
        offer.ratifier = address(this);
        offer.group = bytes32(vm.randomUint());

        if (isBuy) {
            deal(address(loanToken), maker, assets);
            vm.prank(maker);
            loanToken.approve(address(midnight), type(uint256).max);
        } else {
            midnight.supplyCollateral(market, 0, assets / 2, maker);
            midnight.supplyCollateral(market, 1, assets / 2, maker);
        }
    }

    /// @dev Ratifier for external offers built by makeExternalOffer.
    function isRatified(Offer memory, bytes memory, address) external pure returns (bytes32) {
        return CALLBACK_SUCCESS;
    }

    function forceDeallocate(Market memory market, uint256 assets) internal {
        deal(address(loanToken), address(this), loanToken.balanceOf(address(this)) + assets);
        loanToken.approve(address(adapter), assets);
        parentVault.forceDeallocate(address(adapter), claimData(market, address(this)), assets, address(this));
    }

    function claimData(Market memory market, address receiver) internal pure returns (bytes memory) {
        return abi.encode(market, receiver);
    }

    function setUpRealVault() internal {
        realVault = IVaultV2(deployCode("VaultV2.sol:VaultV2", abi.encode(owner, address(loanToken))));
        vm.prank(owner);
        realVault.setCurator(curator);
        adapter = IMidnightAdapter(factory.createMidnightAdapter(address(realVault)));
        setShortfallParams(0.005e18, 1 days);
        disableDurationCaps(adapter);
        setUpMaxTtm(type(uint32).max);

        submitAndCall(realVault, abi.encodeCall(IVaultV2.addAdapter, (address(adapter))));
        submitAndCall(realVault, abi.encodeCall(IVaultV2.setIsAllocator, (address(adapter), true)));
        submitAndCall(realVault, abi.encodeCall(IVaultV2.setIsAllocator, (signerAllocator, true)));
        addSubRatifier(adapter, address(priceRatifier));
        submitAndCall(realVault, abi.encodeCall(IVaultV2.setForceDeallocatePenalty, (address(adapter), 0.02e18)));
        submitAndCall(realVault, abi.encodeCall(IVaultV2.setPerformanceFeeRecipient, (recipient)));
        submitAndCall(realVault, abi.encodeCall(IVaultV2.setManagementFeeRecipient, (recipient)));
        submitAndCall(realVault, abi.encodeCall(IVaultV2.setPerformanceFee, (0.1e18)));
        submitAndCall(realVault, abi.encodeCall(IVaultV2.setManagementFee, (1e9)));
        vm.prank(signerAllocator);
        realVault.setMaxRate(1e18 / uint256(365 days));

        bytes[] memory idDatas = new bytes[](8);
        idDatas[0] = abi.encode("this", address(adapter));
        idDatas[1] = abi.encode("collateralToken", storedCollaterals[0].token);
        idDatas[2] = abi.encode("collateralParams", storedCollaterals[0]);
        idDatas[3] = abi.encode("collateralToken", storedCollaterals[1].token);
        idDatas[4] = abi.encode("collateralParams", storedCollaterals[1]);
        idDatas[5] = abi.encode("enterGate", address(0));
        idDatas[6] = abi.encode("liquidatorGate", address(0));
        idDatas[7] = abi.encode("rcfThreshold", uint256(0));
        for (uint256 i = 0; i < idDatas.length; i++) {
            submitAndCall(realVault, abi.encodeCall(IVaultV2.increaseAbsoluteCap, (idDatas[i], type(uint128).max)));
            submitAndCall(realVault, abi.encodeCall(IVaultV2.increaseRelativeCap, (idDatas[i], 1e18)));
        }

        deal(address(loanToken), address(this), 10e18);
        loanToken.approve(address(realVault), type(uint256).max);
        realVault.deposit(10e18, address(this));
    }

    function buyOnRealVault(uint256 duration, uint256 assets) internal returns (Offer memory offer) {
        offer = makeBuyOffer(duration, assets, MAX_TICK);
        offer.maker = address(adapter);
        offer.callback = address(adapter);
        offer.ratifier = address(adapter);
        midnight.supplyCollateral(offer.market, 0, assets / 2, taker);
        midnight.supplyCollateral(offer.market, 1, assets / 2, taker);
        take(offer);
    }

    function forceDeallocateOnRealVault(Market memory market, uint256 assets) internal returns (uint256) {
        deal(address(loanToken), address(this), loanToken.balanceOf(address(this)) + assets);
        loanToken.approve(address(adapter), assets);
        return realVault.forceDeallocate(address(adapter), claimData(market, address(this)), assets, address(this));
    }

    function submitAndCall(IVaultV2 vault, bytes memory call_) internal {
        vm.prank(curator);
        vault.submit(call_);
        (bool success, bytes memory returnData) = address(vault).call(call_);
        if (!success) {
            assembly ("memory-safe") {
                revert(add(32, returnData), mload(returnData))
            }
        }
    }

    function setMidnightCredit(bytes32 marketId, address account, uint256 credit) internal {
        stdstore.target(address(midnight)).sig("credit(bytes32,address)").with_key(marketId).with_key(account)
            .checked_write(credit);
    }

    function assertCurrentNetCredit(Market memory market, uint256 growth) internal view {
        bytes32 marketId = _marketId(market);
        (uint128 credit, uint128 pendingFee,) = midnight.updatePositionView(market, marketId, address(adapter));
        assertEq(adapter.midnightCredit(market), credit, "gross credit after fees and losses");
        uint256 netCredit = credit - pendingFee;
        uint256 timeToMaturity = market.maturity.zeroFloorSub(block.timestamp);
        assertEq(
            adapter.realAssets(),
            netCredit - netCredit.mulDivUp(growth * timeToMaturity, 1e18),
            "real maturity still determines growth"
        );
    }

    function assertMarketIndex(bytes32 marketId, uint256 expected) internal view {
        assertEq(adapter.marketIds(expected), marketId, "market at expected index");
    }

    function checkMarkets(bytes32[] memory expected) internal view {
        uint256 length = adapter.marketIdsLength();
        assertEq(length, expected.length, "marketIdsLength");
        for (uint256 i = 0; i < expected.length; i++) {
            bool found;
            for (uint256 j = 0; j < length; j++) {
                found = found || adapter.marketIds(j) == expected[i];
            }
            assertTrue(found, "missing market");
        }
    }

    function assertMarkets(bytes32[1] memory m) internal view {
        bytes32[] memory arr = new bytes32[](1);
        arr[0] = m[0];
        checkMarkets(arr);
    }

    function assertMarkets(bytes32[2] memory m) internal view {
        bytes32[] memory arr = new bytes32[](2);
        arr[0] = m[0];
        arr[1] = m[1];
        checkMarkets(arr);
    }

    function assertMarkets(bytes32[3] memory m) internal view {
        bytes32[] memory arr = new bytes32[](3);
        arr[0] = m[0];
        arr[1] = m[1];
        arr[2] = m[2];
        checkMarkets(arr);
    }

    function _marketId(Market memory market) internal pure returns (bytes32) {
        return IdLib.toId(market);
    }

    function ratify(Offer[1] memory offers, address signer) internal returns (bytes memory) {
        return ratifierData(root(offers), signer, 0, proof(offers));
    }

    function proof(Offer[1] memory) internal pure returns (bytes32[] memory) {
        return new bytes32[](0);
    }

    // assumes the offer is the first one!
    function proof(Offer[2] memory offers) internal pure returns (bytes32[] memory) {
        bytes32[] memory path = new bytes32[](1);
        path[0] = HashLib.hashPriceRatifierV1Offer(offers[1], address(0));
        return path;
    }

    function root(Offer memory offer) internal pure returns (bytes32) {
        return HashLib.hashPriceRatifierV1Offer(offer, address(0));
    }

    function root(Offer[1] memory offers) internal pure returns (bytes32) {
        return HashLib.hashPriceRatifierV1Offer(offers[0], address(0));
    }

    function root(Offer[2] memory offers) internal pure returns (bytes32) {
        return HashLib.hashNode(
            HashLib.hashPriceRatifierV1Offer(offers[0], address(0)),
            HashLib.hashPriceRatifierV1Offer(offers[1], address(0))
        );
    }

    function ratifierData(bytes32 _root, address signer) internal returns (bytes memory) {
        bytes32[] memory emptyProof = new bytes32[](0);
        return ratifierData(_root, signer, 0, emptyProof);
    }

    function ratifierData(bytes32 _root, address signer, uint256 leafIndex, bytes32[] memory _proof)
        internal
        returns (bytes memory)
    {
        vm.prank(signer);
        priceRatifier.setIsRootRatified(address(adapter), _root, true);
        return abi.encode(address(priceRatifier), abi.encode(_root, leafIndex, _proof, address(0)));
    }

    function freshPosition(uint256 tick) internal returns (Offer memory offer) {
        setUpRealVault();
        storedOffer.maker = address(adapter);
        storedOffer.ratifier = address(adapter);
        offer = makeBuyOffer(7 days, 8e18, tick);
        midnight.supplyCollateral(offer.market, 0, offer.maxUnits / 2, taker);
        midnight.supplyCollateral(offer.market, 1, offer.maxUnits - offer.maxUnits / 2, taker);
        directTake(offer);
        deal(address(loanToken), taker, 100e18);
    }

    function directTake(Offer memory offer) internal {
        this.ratifyAndDirectTake(offer);
    }

    function ratifyAndDirectTake(Offer memory offer) external {
        bytes memory data = ratify([offer], signerAllocator);
        vm.prank(taker);
        midnight.take(offer, data, offer.maxUnits, taker, offer.buy ? taker : address(0), address(0), "");
    }

    function newCallback() internal returns (EagerLossCallback callback) {
        callback = new EagerLossCallback(address(midnight), address(loanToken), address(realVault));
        deal(address(loanToken), address(callback), 100e18);
    }

    function callbackSale(Offer memory offer, EagerLossCallback callback) internal {
        this.ratifyAndCallbackSale(offer, callback);
    }

    function ratifyAndCallbackSale(Offer memory offer, EagerLossCallback callback) external {
        midnight.take(
            offer,
            ratify([offer], signerAllocator),
            offer.maxUnits,
            address(callback),
            address(0),
            address(callback),
            ""
        );
    }

    function accruedCallbackSale(Offer memory offer, EagerLossCallback callback) external {
        realVault.accrueInterest();
        callbackSale(offer, callback);
    }

    function realizeDefault(Market memory market, uint256 price) external {
        OracleMock(storedCollaterals[0].oracle).setPrice(price);
        OracleMock(storedCollaterals[1].oracle).setPrice(price);
        midnight.liquidate(market, 0, 0, 0, taker, false, address(this), address(0), "");
    }

    function backing() internal view returns (uint256) {
        return loanToken.balanceOf(address(realVault)) + adapter.realAssets();
    }

    function testEagerLossDeploymentSize() public view {
        assertLe(address(adapter).code.length, 24576, "adapter runtime size");
        assertLe(address(factory).code.length, 24576, "factory runtime size");
    }

    /// forge-config: default.isolate = true
    function testEagerLossDirectInitialBuy() public {
        freshPosition(MAX_TICK);
        assertEq(realVault._totalAssets(), 10e18);
        assertEq(backing(), 10e18);
        assertEq(adapter.realAssets(), 8e18);
    }

    /// forge-config: default.isolate = true
    function testEagerLossDirectParSale() public {
        Offer memory initial = freshPosition(MAX_TICK);
        assertEq(realVault.firstTotalAssets(), 0);
        directTake(makeSellOffer(initial.market, 4e18, MAX_TICK));
        assertEq(realVault._totalAssets(), 10e18);
        assertEq(backing(), 10e18);
    }

    /// forge-config: default.isolate = true
    function testEagerLossDirectSaleAfterDefault() public {
        Offer memory initial = freshPosition(MAX_TICK);
        this.realizeDefault(initial.market, ORACLE_PRICE_SCALE / 2);
        uint256 expected = realVault.totalAssets();
        assertApproxEqAbs(expected, 6e18, 1);
        directTake(makeSellOffer(initial.market, 2e18, MAX_TICK));
        assertEq(realVault._totalAssets(), 10e18);
        assertEq(realVault.totalAssets(), expected);
        assertEq(backing(), expected);
    }

    /// forge-config: default.isolate = true
    function testEagerLossDirectBuyAfterDefault() public {
        Offer memory initial = freshPosition(MAX_TICK);
        this.realizeDefault(initial.market, ORACLE_PRICE_SCALE / 2);
        uint256 expected = realVault.totalAssets();
        Offer memory offer = makeBuyOffer(7 days, 1e18, MAX_TICK);
        offer.group = bytes32("second purchase");
        midnight.supplyCollateral(initial.market, 0, 2e18, taker);
        directTake(offer);
        assertEq(realVault._totalAssets(), expected);
        assertEq(backing(), expected);
    }

    /// forge-config: default.isolate = true
    function testEagerLossUncoveredSaleReverts() public {
        Offer memory initial = freshPosition(MAX_TICK);
        setMaxSellRate(initial.market, 1);
        Offer memory offer = makeSellOffer(initial.market, 4e18, MAX_TICK / 2);
        vm.expectRevert(IMidnightAdapterBase.SellRateTooHigh.selector);
        directTake(offer);
    }

    /// forge-config: default.isolate = true
    function testEagerLossUncoveredSaleAfterDefaultReverts() public {
        Offer memory initial = freshPosition(MAX_TICK);
        setMaxSellRate(initial.market, 1);
        this.realizeDefault(initial.market, ORACLE_PRICE_SCALE / 2);
        Offer memory offer = makeSellOffer(initial.market, 2e18, MAX_TICK / 2);
        vm.expectRevert(IMidnightAdapterBase.SellRateTooHigh.selector);
        directTake(offer);
    }

    /// forge-config: default.isolate = true
    function testEagerLossAllowedDiscountedSale() public {
        Offer memory initial = freshPosition(MAX_TICK);
        skip(2 days);
        deal(address(loanToken), address(realVault), 6e18);
        setMaxSellRate(initial.market, uint256(1e18).mulDivUp(1, initial.market.maturity - block.timestamp));
        directTake(makeSellOffer(initial.market, 0.08e18, MAX_TICK / 2));
        assertEq(realVault._totalAssets(), 10e18);
        assertGe(backing(), 10e18);
    }

    /// forge-config: default.isolate = true
    function testEagerLossCallbackFirstValuationAfterDefaultBlocked() public {
        Offer memory initial = freshPosition(MAX_TICK);
        this.realizeDefault(initial.market, ORACLE_PRICE_SCALE / 2);
        uint256 expected = realVault.totalAssets();
        EagerLossCallback callback = newCallback();
        callback.push(
            address(adapter), abi.encodeCall(IAdapter.realAssets, ()), IMidnightAdapterBase.OtherSellInProgress.selector
        );
        callback.push(
            address(realVault),
            abi.encodeCall(IVaultV2.accrueInterest, ()),
            IMidnightAdapterBase.OtherSellInProgress.selector
        );
        callback.push(
            address(realVault),
            abi.encodeCall(realVault.deposit, (1e18, recipient)),
            IMidnightAdapterBase.OtherSellInProgress.selector
        );
        callbackSale(makeSellOffer(initial.market, 2e18, MAX_TICK), callback);
        assertEq(realVault._totalAssets(), 10e18);
        assertEq(realVault.totalAssets(), expected);
        assertEq(backing(), expected);
        assertEq(realVault.balanceOf(recipient), 0);
    }

    /// forge-config: default.isolate = true
    function testEagerLossCallbackValuationWithoutLossBlocked() public {
        Offer memory initial = freshPosition(MAX_TICK);
        EagerLossCallback callback = newCallback();
        callback.push(
            address(adapter), abi.encodeCall(IAdapter.realAssets, ()), IMidnightAdapterBase.OtherSellInProgress.selector
        );
        callback.push(
            address(realVault),
            abi.encodeCall(IVaultV2.accrueInterest, ()),
            IMidnightAdapterBase.OtherSellInProgress.selector
        );
        callback.push(
            address(realVault),
            abi.encodeCall(realVault.deposit, (1e18, recipient)),
            IMidnightAdapterBase.OtherSellInProgress.selector
        );
        callbackSale(makeSellOffer(initial.market, 4e18, MAX_TICK), callback);
        assertEq(realVault._totalAssets(), 10e18);
        assertEq(backing(), 10e18);
        assertEq(realVault.balanceOf(recipient), 0);
    }

    /// forge-config: default.isolate = true
    function testEagerLossPreaccruedCallbackDepositWorks() public {
        Offer memory initial = freshPosition(MAX_TICK);
        EagerLossCallback callback = newCallback();
        callback.push(address(realVault), abi.encodeCall(realVault.deposit, (1e18, recipient)), bytes4(0));
        this.accruedCallbackSale(makeSellOffer(initial.market, 4e18, MAX_TICK), callback);
        assertEq(realVault._totalAssets(), 11e18);
        assertEq(backing(), 11e18);
        assertEq(realVault.balanceOf(recipient), 1e18);
    }

    /// forge-config: default.isolate = true
    function testEagerLossDefaultDuringParSale() public {
        Offer memory initial = freshPosition(MAX_TICK);
        EagerLossCallback callback = newCallback();
        callback.push(
            address(this), abi.encodeCall(this.realizeDefault, (initial.market, ORACLE_PRICE_SCALE / 2)), bytes4(0)
        );
        callbackSale(makeSellOffer(initial.market, 4e18, MAX_TICK), callback);
        assertApproxEqAbs(backing(), 8e18, 1);
        assertEq(realVault._totalAssets(), 10e18);
        assertEq(realVault.totalAssets(), backing());
    }

    /// forge-config: default.isolate = true
    function testEagerLossDefaultDuringDiscountedSaleReverts() public {
        Offer memory initial = freshPosition(MAX_TICK);
        setMaxSellRate(initial.market, 1);
        EagerLossCallback callback = newCallback();
        callback.push(
            address(this), abi.encodeCall(this.realizeDefault, (initial.market, ORACLE_PRICE_SCALE / 2)), bytes4(0)
        );
        Offer memory offer = makeSellOffer(initial.market, 4e18, MAX_TICK / 2);
        vm.expectRevert(IMidnightAdapterBase.SellRateTooHigh.selector);
        callbackSale(offer, callback);
    }

    /// forge-config: default.isolate = true
    function testEagerLossFullSaleThenCompleteDefault() public {
        Offer memory initial = freshPosition(MAX_TICK);
        EagerLossCallback callback = newCallback();
        callback.push(address(this), abi.encodeCall(this.realizeDefault, (initial.market, 0)), bytes4(0));
        callbackSale(makeSellOffer(initial.market, 8e18, MAX_TICK), callback);
        assertEq(backing(), 10e18);
        assertEq(realVault._totalAssets(), 10e18);
        assertEq(adapter.marketIdsLength(), 0);
    }

    /// forge-config: default.isolate = true
    function testEagerLossDefaultAndPositionUpdateDuringSale() public {
        Offer memory initial = freshPosition(MAX_TICK);
        EagerLossCallback callback = newCallback();
        callback.push(
            address(this), abi.encodeCall(this.realizeDefault, (initial.market, ORACLE_PRICE_SCALE / 2)), bytes4(0)
        );
        callback.push(
            address(midnight), abi.encodeCall(IMidnight.updatePosition, (initial.market, address(adapter))), bytes4(0)
        );
        callbackSale(makeSellOffer(initial.market, 4e18, MAX_TICK), callback);
        assertApproxEqAbs(backing(), 8e18, 1);
        assertEq(realVault._totalAssets(), 10e18);
        assertEq(realVault.totalAssets(), backing());
    }

    /// forge-config: default.isolate = true
    function testEagerLossSameMarketMutationsBlocked() public {
        Offer memory initial = freshPosition(MAX_TICK);
        EagerLossCallback callback = newCallback();
        submitAndCall(realVault, abi.encodeCall(IVaultV2.setIsAllocator, (address(callback), true)));
        Offer memory innerBuy = makeBuyOffer(7 days, 1e18, MAX_TICK);
        innerBuy.group = bytes32("nested purchase");
        callback.push(
            address(midnight),
            abi.encodeCall(
                IMidnight.take,
                (
                    innerBuy,
                    ratify([innerBuy], signerAllocator),
                    innerBuy.maxUnits,
                    address(callback),
                    address(callback),
                    address(0),
                    ""
                )
            ),
            IMidnightAdapterBase.SellInProgress.selector
        );
        Offer memory innerSell = makeSellOffer(initial.market, 1e18, MAX_TICK);
        callback.push(
            address(midnight),
            abi.encodeCall(
                IMidnight.take,
                (
                    innerSell,
                    ratify([innerSell], signerAllocator),
                    innerSell.maxUnits,
                    address(callback),
                    address(0),
                    address(0),
                    ""
                )
            ),
            IMidnightAdapterBase.SellInProgress.selector
        );
        callback.push(
            address(adapter),
            abi.encodeCall(IMidnightAdapterBase.withdrawToVault, (initial.market, 0)),
            IMidnightAdapterBase.SellInProgress.selector
        );
        bytes memory data = claimData(initial.market, address(callback));
        callback.push(
            address(realVault),
            abi.encodeCall(IVaultV2.forceDeallocate, (address(adapter), data, 1e15, address(callback))),
            IMidnightAdapterBase.SellInProgress.selector
        );
        Offer memory externalBuy = makeExternalOffer(initial.market, true, 1e18, MAX_TICK);
        callback.push(
            address(adapter),
            abi.encodeCall(IMidnightAdapterBase.take, (externalBuy, "", externalBuy.maxUnits)),
            IMidnightAdapterBase.SellInProgress.selector
        );
        callbackSale(makeSellOffer(initial.market, 4e18, MAX_TICK), callback);
        assertEq(realVault._totalAssets(), 10e18);
        assertEq(backing(), 10e18);
    }

    /// forge-config: default.isolate = true
    function testEagerLossCrossMarketSnapshotBlocked() public {
        Offer memory initial = freshPosition(MAX_TICK);
        this.realizeDefault(initial.market, ORACLE_PRICE_SCALE / 2);
        uint256 expected = realVault.totalAssets();
        EagerLossCallback callback = newCallback();
        Offer memory inner = makeBuyOffer(6 days, 1e18, MAX_TICK);
        callback.push(
            address(midnight),
            abi.encodeCall(
                IMidnight.take,
                (
                    inner,
                    ratify([inner], signerAllocator),
                    inner.maxUnits,
                    address(callback),
                    address(callback),
                    address(0),
                    ""
                )
            ),
            IMidnightAdapterBase.OtherSellInProgress.selector
        );
        callbackSale(makeSellOffer(initial.market, 2e18, MAX_TICK), callback);
        assertEq(realVault._totalAssets(), 10e18);
        assertEq(realVault.totalAssets(), expected);
        assertEq(backing(), expected);
    }

    /// forge-config: default.isolate = true
    function testEagerLossCrossMarketBuyRequiresSnapshot(bool accrued) public {
        Offer memory initial = freshPosition(MAX_TICK);
        EagerLossCallback callback = newCallback();
        Offer memory inner = makeBuyOffer(6 days, 1e18, MAX_TICK);
        midnight.supplyCollateral(inner.market, 0, 2e18, address(callback));
        callback.push(
            address(midnight),
            abi.encodeCall(
                IMidnight.take,
                (
                    inner,
                    ratify([inner], signerAllocator),
                    inner.maxUnits,
                    address(callback),
                    address(callback),
                    address(0),
                    ""
                )
            ),
            accrued ? bytes4(0) : IMidnightAdapterBase.OtherSellInProgress.selector
        );
        if (accrued) {
            this.accruedCallbackSale(makeSellOffer(initial.market, 4e18, MAX_TICK), callback);
        } else {
            callbackSale(makeSellOffer(initial.market, 4e18, MAX_TICK), callback);
        }
        assertEq(realVault._totalAssets(), 10e18);
        assertEq(backing(), 10e18);
        assertEq(adapter.marketData(_marketId(initial.market)).netCredit, 4e18);
        assertEq(adapter.marketData(_marketId(inner.market)).netCredit, accrued ? 1e18 : 0);
    }

    /// forge-config: default.isolate = true
    function testEagerLossCrossMarketFullSaleDuringSale(bool accrued) public {
        Offer memory initial = freshPosition(MAX_TICK);
        Offer memory second = makeBuyOffer(6 days, 1e18, MAX_TICK);
        midnight.supplyCollateral(second.market, 0, 2e18, taker);
        directTake(second);
        EagerLossCallback callback = newCallback();
        Offer memory inner = makeSellOffer(second.market, 1e18, MAX_TICK);
        callback.push(
            address(midnight),
            abi.encodeCall(
                IMidnight.take,
                (inner, ratify([inner], signerAllocator), inner.maxUnits, address(callback), address(0), address(0), "")
            ),
            bytes4(0)
        );
        if (accrued) {
            this.accruedCallbackSale(makeSellOffer(initial.market, 8e18, MAX_TICK), callback);
        } else {
            callbackSale(makeSellOffer(initial.market, 8e18, MAX_TICK), callback);
        }
        assertEq(realVault._totalAssets(), 10e18);
        assertEq(backing(), 10e18);
        assertEq(adapter.marketIdsLength(), 0);
        assertEq(adapter.marketData(_marketId(initial.market)).netCredit, 0);
        assertEq(adapter.marketData(_marketId(second.market)).netCredit, 0);
    }

    /// forge-config: default.isolate = true
    function testEagerLossDefaultDuringSaleBlocksOnlyUnassistedReads() public {
        Offer memory initial = freshPosition(MAX_TICK);
        EagerLossCallback callback = newCallback();
        callback.push(
            address(this), abi.encodeCall(this.realizeDefault, (initial.market, ORACLE_PRICE_SCALE / 2)), bytes4(0)
        );
        callback.push(
            address(adapter), abi.encodeCall(IAdapter.realAssets, ()), IMidnightAdapterBase.OtherSellInProgress.selector
        );
        callback.push(
            address(realVault),
            abi.encodeCall(IVaultV2.accrueInterest, ()),
            IMidnightAdapterBase.OtherSellInProgress.selector
        );
        callback.push(
            address(realVault),
            abi.encodeCall(realVault.deposit, (1e18, recipient)),
            IMidnightAdapterBase.OtherSellInProgress.selector
        );
        this.saleThenDeposit(makeSellOffer(initial.market, 4e18, MAX_TICK), callback);
        assertApproxEqAbs(backing(), 9e18, 1);
        assertEq(realVault._totalAssets(), backing());
    }

    function saleThenDeposit(Offer memory offer, EagerLossCallback callback) external {
        callbackSale(offer, callback);
        assertFalse(midnight.liquidationLocked(_marketId(offer.market), address(adapter)));
        assertEq(realVault.firstTotalAssets(), 0);
        assertEq(realVault.totalAssets(), backing());
        deal(address(loanToken), address(this), 1e18);
        realVault.deposit(1e18, recipient);
    }

    /// forge-config: default.isolate = true
    function testEagerLossPartialSaleThenCompleteDefault() public {
        Offer memory initial = freshPosition(MAX_TICK);
        EagerLossCallback callback = newCallback();
        callback.push(address(this), abi.encodeCall(this.realizeDefault, (initial.market, 0)), bytes4(0));
        callback.push(
            address(adapter), abi.encodeCall(IAdapter.realAssets, ()), IMidnightAdapterBase.OtherSellInProgress.selector
        );
        callback.push(
            address(realVault),
            abi.encodeCall(IVaultV2.accrueInterest, ()),
            IMidnightAdapterBase.OtherSellInProgress.selector
        );
        callbackSale(makeSellOffer(initial.market, 4e18, MAX_TICK), callback);
        assertEq(realVault._totalAssets(), 10e18);
        assertEq(realVault.totalAssets(), 6e18);
        assertEq(backing(), 6e18);
        assertEq(adapter.marketIdsLength(), 0);
    }

    /// forge-config: default.isolate = true
    function testEagerLossSaleThenDefault(bool zeroSnapshot) public {
        Offer memory initial = freshPosition(MAX_TICK);
        if (zeroSnapshot) {
            stdstore.enable_packed_slots().target(address(realVault)).sig("_totalAssets()").checked_write(uint256(0));
        }
        this.saleThenDefault(makeSellOffer(initial.market, 4e18, MAX_TICK), zeroSnapshot);
    }

    function saleThenDefault(Offer memory offer, bool zeroSnapshot) external {
        directTake(offer);
        assertEq(realVault.firstTotalAssets(), 0);
        assertEq(adapter.realAssets(), 4e18);
        this.realizeDefault(offer.market, 0);
        assertEq(adapter.realAssets(), 0, "temporary valuation cleared in the same transaction");
        realVault.accrueInterest();
        assertEq(realVault.firstTotalAssets(), zeroSnapshot ? 0 : 6e18);
        assertEq(realVault.totalAssets(), zeroSnapshot ? 0 : 6e18);
    }

    /// forge-config: default.isolate = true
    function testEagerLossSaleDoesNotAccrue(bool takerSale) public {
        Offer memory initial = freshPosition(MAX_TICK);
        Offer memory offer = takerSale
            ? makeExternalOffer(initial.market, true, 4e18, MAX_TICK)
            : makeSellOffer(initial.market, 4e18, MAX_TICK);
        this.saleWithoutAccrual(offer, takerSale);
        assertEq(backing(), 10e18);
    }

    function saleWithoutAccrual(Offer memory offer, bool takerSale) external {
        assertEq(realVault.firstTotalAssets(), 0);
        uint256 storedAssets = realVault._totalAssets();
        uint256 lastUpdate = realVault.lastUpdate();
        if (takerSale) {
            vm.prank(signerAllocator);
            adapter.take(offer, "", offer.maxUnits);
        } else {
            directTake(offer);
        }
        assertEq(realVault.firstTotalAssets(), 0, "sale does not establish a snapshot");
        assertEq(realVault._totalAssets(), storedAssets, "sale does not change stored assets");
        assertEq(realVault.lastUpdate(), lastUpdate, "sale does not advance accrual");
    }

    /// forge-config: default.isolate = true
    function testEagerLossSequentialSalesInSameTransaction() public {
        Offer memory initial = freshPosition(MAX_TICK);
        this.sequentialSales(initial.market);
    }

    function sequentialSales(Market memory market) external {
        directTake(makeSellOffer(market, 2e18, MAX_TICK));
        directTake(makeSellOffer(market, 2e18, MAX_TICK));
        assertEq(realVault._totalAssets(), 10e18);
        assertEq(backing(), 10e18);
    }

    uint256 internal expectedSaleBaseline;

    function recordSaleBaseline(Market memory market, uint256 soldNet, uint256 oldNet, uint256 remainingInterest)
        external
    {
        (uint128 credit, uint128 pendingFee,) = midnight.updatePositionView(market, _marketId(market), address(adapter));
        uint256 reconstructed = credit - pendingFee + soldNet;
        uint256 value = reconstructed - remainingInterest.mulDivUp(reconstructed, oldNet);
        uint256 cap = uint256(realVault._totalAssets())
            + uint256(realVault._totalAssets())
                .mulDivDown((block.timestamp - realVault.lastUpdate()) * realVault.maxRate(), 1e18);
        expectedSaleBaseline = MathLib.min(loanToken.balanceOf(address(realVault)) + value, cap);
    }

    /// forge-config: default.isolate = true
    function testEagerLossFuzzDefaultDuringSale(uint256 elapsed, uint256 fee, uint256 sold, bool updatePosition)
        public
    {
        midnight.setDefaultContinuousFee(address(loanToken), bound(fee, 0, MAX_CONTINUOUS_FEE));
        Offer memory initial = freshPosition(TickLib.priceToTick(0.9e18, DEFAULT_TICK_SPACING));
        skip(bound(elapsed, 0, 7 days));
        (uint128 credit, uint128 pendingFee,) =
            midnight.updatePositionView(initial.market, _marketId(initial.market), address(adapter));
        sold = bound(sold, 1, credit);
        uint256 soldNet = sold - uint256(pendingFee).mulDivUp(sold, credit);
        uint256 oldNet = credit - pendingFee;
        uint256 remainingInterest = oldNet - adapter.realAssets();
        EagerLossCallback callback = newCallback();
        callback.push(
            address(this), abi.encodeCall(this.realizeDefault, (initial.market, ORACLE_PRICE_SCALE / 2)), bytes4(0)
        );
        if (updatePosition) {
            callback.push(
                address(midnight),
                abi.encodeCall(IMidnight.updatePosition, (initial.market, address(adapter))),
                bytes4(0)
            );
        }
        callback.push(
            address(this),
            abi.encodeCall(this.recordSaleBaseline, (initial.market, soldNet, oldNet, remainingInterest)),
            bytes4(0)
        );
        uint256 storedAssets = realVault._totalAssets();
        callbackSale(makeSellOffer(initial.market, sold, MAX_TICK), callback);
        assertEq(realVault._totalAssets(), storedAssets, "sale does not accrue");
        assertGe(realVault.totalAssets(), expectedSaleBaseline);
        assertGe(backing(), expectedSaleBaseline);
    }

    /// forge-config: default.isolate = true
    function testEagerLossFuzzSaleBaseline(uint256 elapsed, uint256 fee, uint256 sold, bool loss) public {
        fee = bound(fee, 0, MAX_CONTINUOUS_FEE);
        midnight.setDefaultContinuousFee(address(loanToken), fee);
        Offer memory initial = freshPosition(TickLib.priceToTick(0.9e18, DEFAULT_TICK_SPACING));
        skip(bound(elapsed, 0, 7 days));
        if (loss) this.realizeDefault(initial.market, ORACLE_PRICE_SCALE / 2);
        (uint128 credit,,) = midnight.updatePositionView(initial.market, _marketId(initial.market), address(adapter));
        sold = bound(sold, 1, credit);
        uint256 expected = realVault.totalAssets();
        uint256 storedAssets = realVault._totalAssets();
        directTake(makeSellOffer(initial.market, sold, MAX_TICK));
        assertEq(realVault._totalAssets(), storedAssets, "sale does not accrue");
        assertGe(realVault.totalAssets(), expected, "pre-sale baseline preserved");
        assertGe(backing(), expected, "covered sale");
    }

    /// forge-config: default.isolate = true
    function testEagerLossFuzzBuyAfterDefault(uint256 elapsed, uint256 fee, uint256 assets) public {
        fee = bound(fee, 0, MAX_CONTINUOUS_FEE);
        midnight.setDefaultContinuousFee(address(loanToken), fee);
        Offer memory initial = freshPosition(TickLib.priceToTick(0.9e18, DEFAULT_TICK_SPACING));
        elapsed = bound(elapsed, 0, 7 days - 1);
        skip(elapsed);
        this.realizeDefault(initial.market, ORACLE_PRICE_SCALE / 2);
        uint256 expected = realVault.totalAssets();
        Offer memory offer = makeBuyOffer(7 days - elapsed, bound(assets, 1e12, 1e18), initial.tick);
        offer.group = bytes32("purchase after default");
        midnight.supplyCollateral(initial.market, 0, offer.maxUnits * 2 + 1e18, taker);
        directTake(offer);
        assertEq(realVault._totalAssets(), expected, "newly bought credit excluded");
        assertGe(backing() + 1, expected, "rounding only");
    }

    /// forge-config: default.isolate = true
    function testEagerLossSelfFunding(bool sameMarket, bool fullWithdrawal) public {
        Offer memory initial = freshPosition(MAX_TICK);
        vm.prank(taker);
        midnight.repay(initial.market, 8e18, taker, address(0), "");

        uint256 withdrawnAssets = fullWithdrawal ? 8e18 : 3e18;
        Offer memory offer = makeBuyOffer(sameMarket ? 7 days : 6 days, 2e18 + withdrawnAssets, MAX_TICK);
        offer.group = bytes32("self-funded purchase");
        offer.callbackData = abi.encode(address(adapter), abi.encode(initial.market));
        midnight.supplyCollateral(offer.market, 0, offer.maxUnits, taker);

        vm.expectEmit(address(adapter));
        emit IMidnightAdapterBase.WithdrawToVault(
            _marketId(initial.market), withdrawnAssets, sameMarket ? 10e18 : 8e18 - withdrawnAssets, 0
        );
        directTake(offer);

        assertEq(adapter.marketData(_marketId(initial.market)).netCredit, sameMarket ? 10e18 : 8e18 - withdrawnAssets);
        assertEq(adapter.marketData(_marketId(offer.market)).netCredit, sameMarket ? 10e18 : offer.maxUnits);
        assertEq(adapter.marketIdsLength(), sameMarket || fullWithdrawal ? 1 : 2);
        assertEq(midnight.withdrawable(_marketId(initial.market)), 8e18 - withdrawnAssets);
        assertEq(realVault.allocation(adapter.adapterId()), 10e18);
        assertEq(loanToken.balanceOf(address(realVault)), 0);
        assertEq(loanToken.balanceOf(address(adapter)), 0);
        assertEq(realVault._totalAssets(), 10e18);
        assertEq(backing(), 10e18);
    }

    /// forge-config: default.isolate = true
    function testEagerLossSelfFundingAfterLoss(bool sameMarket) public {
        Offer memory initial = freshPosition(MAX_TICK);
        vm.prank(taker);
        midnight.repay(initial.market, 4e18, taker, address(0), "");
        this.realizeDefault(initial.market, 0);
        OracleMock(storedCollaterals[0].oracle).setPrice(ORACLE_PRICE_SCALE);
        OracleMock(storedCollaterals[1].oracle).setPrice(ORACLE_PRICE_SCALE);
        uint256 expected = realVault.totalAssets();
        assertApproxEqAbs(expected, 6e18, 1);

        Offer memory offer = makeBuyOffer(sameMarket ? 7 days : 6 days, 3e18, MAX_TICK);
        offer.group = bytes32("self-funded purchase");
        offer.callbackData = abi.encode(address(adapter), abi.encode(initial.market));
        midnight.supplyCollateral(offer.market, 0, offer.maxUnits, taker);
        directTake(offer);

        assertEq(adapter.marketData(_marketId(initial.market)).netCredit, sameMarket ? expected : expected - 3e18);
        assertEq(adapter.marketData(_marketId(offer.market)).netCredit, sameMarket ? expected : 3e18);
        assertEq(midnight.withdrawable(_marketId(initial.market)), 3e18);
        assertEq(realVault.allocation(adapter.adapterId()), expected);
        assertEq(loanToken.balanceOf(address(realVault)), 0);
        assertEq(realVault._totalAssets(), expected);
        assertEq(backing(), expected);
    }

    /// forge-config: default.isolate = true
    function testEagerLossSelfFundingSkippedWithEnoughIdleAssets() public {
        Offer memory initial = freshPosition(MAX_TICK);
        Offer memory offer = makeBuyOffer(6 days, 1e18, MAX_TICK);
        offer.callbackData = abi.encode(address(adapter), hex"01");
        midnight.supplyCollateral(offer.market, 0, offer.maxUnits, taker);
        directTake(offer);

        assertEq(adapter.marketData(_marketId(initial.market)).netCredit, 8e18);
        assertEq(adapter.marketData(_marketId(offer.market)).netCredit, 1e18);
        assertEq(loanToken.balanceOf(address(realVault)), 1e18);
        assertEq(realVault._totalAssets(), 10e18);
        assertEq(backing(), 10e18);
    }

    /// forge-config: default.isolate = true
    function testEagerLossSelfFundingInsufficientLiquidityReverts() public {
        Offer memory initial = freshPosition(MAX_TICK);
        Offer memory offer = makeBuyOffer(6 days, 3e18, MAX_TICK);
        offer.callbackData = abi.encode(address(adapter), abi.encode(initial.market));
        midnight.supplyCollateral(offer.market, 0, offer.maxUnits, taker);

        vm.expectRevert(stdError.arithmeticError);
        directTake(offer);

        assertEq(adapter.marketData(_marketId(initial.market)).netCredit, 8e18);
        assertEq(adapter.marketData(_marketId(offer.market)).netCredit, 0);
        assertEq(realVault.allocation(adapter.adapterId()), 8e18);
        assertEq(loanToken.balanceOf(address(realVault)), 2e18);
        assertEq(backing(), 10e18);
    }

    /// forge-config: default.isolate = true
    function testEagerLossSelfFundingDuringSale(bool accrued, bool fundingLocked) public {
        Offer memory initial = freshPosition(MAX_TICK);
        Market memory fundingMarket = initial.market;
        if (!fundingLocked) {
            Offer memory second = makeBuyOffer(6 days, 1e18, MAX_TICK);
            midnight.supplyCollateral(second.market, 0, second.maxUnits, taker);
            directTake(second);
            fundingMarket = second.market;
        }
        vm.prank(taker);
        midnight.repay(fundingMarket, 1e18, taker, address(0), "");

        EagerLossCallback callback = newCallback();
        Offer memory inner = makeBuyOffer(5 days, fundingLocked ? 3e18 : 2e18, MAX_TICK);
        inner.callbackData = abi.encode(address(adapter), abi.encode(fundingMarket));
        midnight.supplyCollateral(inner.market, 0, inner.maxUnits, address(callback));
        bool succeeds = accrued && !fundingLocked;
        callback.push(
            address(midnight),
            abi.encodeCall(
                IMidnight.take,
                (
                    inner,
                    ratify([inner], signerAllocator),
                    inner.maxUnits,
                    address(callback),
                    address(callback),
                    address(0),
                    ""
                )
            ),
            succeeds
                ? bytes4(0)
                : (accrued
                        ? IMidnightAdapterBase.SellInProgress.selector
                        : IMidnightAdapterBase.OtherSellInProgress.selector)
        );
        if (accrued) {
            this.accruedCallbackSale(makeSellOffer(initial.market, 4e18, MAX_TICK), callback);
        } else {
            callbackSale(makeSellOffer(initial.market, 4e18, MAX_TICK), callback);
        }

        assertEq(adapter.marketData(_marketId(initial.market)).netCredit, 4e18);
        assertEq(adapter.marketData(_marketId(inner.market)).netCredit, succeeds ? inner.maxUnits : 0);
        assertEq(midnight.withdrawable(_marketId(fundingMarket)), succeeds ? 0 : 1e18);
        assertEq(realVault.allocation(adapter.adapterId()), fundingLocked ? 4e18 : (succeeds ? 6e18 : 5e18));
        assertEq(realVault._totalAssets(), 10e18);
        assertEq(backing(), 10e18);
    }

    /// forge-config: default.isolate = true
    function testNoCbAccrueLiquidateRedeem() public {
        Offer memory initial = freshPosition(MAX_TICK);
        address exiter = makeAddr("exiter");
        deal(address(loanToken), exiter, 2e18);
        vm.startPrank(exiter);
        loanToken.approve(address(realVault), type(uint256).max);
        realVault.deposit(2e18, exiter);
        vm.stopPrank();
        uint256 exiterShares = realVault.balanceOf(exiter);

        this.accrueLiquidateRedeem(initial.market, exiter, exiterShares);

        assertEq(loanToken.balanceOf(exiter), 2e18, "exited whole");
        assertEq(realVault.totalAssets(), backing(), "loss visible after the tx");
        assertApproxEqAbs(backing(), 10e18 - 4e18, 2, "half of the credit is lost");
    }

    function accrueLiquidateRedeem(Market memory market, address exiter, uint256 shares) external {
        realVault.accrueInterest();
        this.realizeDefault(market, ORACLE_PRICE_SCALE / 2);
        vm.prank(exiter);
        realVault.redeem(shares, exiter, exiter);
    }
}
