// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Morpho Association
pragma solidity ^0.8.0;

import "../lib/forge-std/src/Test.sol";
import {MidnightAdapter} from "../src/adapters/MidnightAdapter.sol";
import {MidnightAdapterFactory} from "../src/adapters/MidnightAdapterFactory.sol";
import {ERC20Mock} from "./mocks/ERC20Mock.sol";
import {OracleMock} from "../lib/morpho-blue/src/mocks/OracleMock.sol";
import {VaultV2Mock} from "./mocks/VaultV2Mock.sol";
import {AdapterMock} from "./mocks/AdapterMock.sol";
import {IERC20} from "../src/interfaces/IERC20.sol";
import {IAdapter} from "../src/interfaces/IAdapter.sol";
import {IMidnightAdapter} from "../src/adapters/interfaces/IMidnightAdapter.sol";
import {MidnightAdapterEcrecoverRatifier} from "../src/adapters/ratifiers/MidnightAdapterEcrecoverRatifier.sol";
import {
    IMidnightAdapterEcrecoverRatifier
} from "../src/adapters/ratifiers/interfaces/IMidnightAdapterEcrecoverRatifier.sol";
import {IVaultV2} from "../src/interfaces/IVaultV2.sol";
import {ISendSharesGate} from "../src/interfaces/IGate.sol";
import {ErrorsLib} from "../src/libraries/ErrorsLib.sol";
import {IMidnightAdapterFactory} from "../src/adapters/interfaces/IMidnightAdapterFactory.sol";
import {MathLib} from "../src/libraries/MathLib.sol";
import {IMidnight, Offer, Market, CollateralParams} from "../lib/midnight/src/interfaces/IMidnight.sol";
import {Signature, EIP712_DOMAIN_TYPEHASH} from "../lib/midnight/src/ratifiers/interfaces/IEcrecoverRatifier.sol";
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

/// @notice Realizes the losses of a midnight adapter in a market.
contract MidnightLossRealizer {
    address public immutable midnight;

    constructor(address _midnight) {
        midnight = _midnight;
        IMidnight(_midnight).setIsAuthorized(address(this), true, address(this));
    }

    function realizeLoss(IMidnightAdapter adapter, Market memory market) external {
        Offer memory offer;
        offer.market = market;
        offer.buy = true;
        offer.maker = address(this);
        offer.expiry = block.timestamp;
        offer.tick = MAX_TICK;
        offer.ratifier = address(this);
        offer.maxUnits = 1;
        offer.continuousFeeCap = type(uint256).max;

        IVaultV2(adapter.parentVault())
            .forceDeallocate(address(adapter), abi.encode(offer, bytes("")), 0, address(this));
    }

    function isRatified(Offer memory, bytes memory, address) external view returns (bytes32) {
        return CALLBACK_SUCCESS;
    }
}

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
    MidnightAdapterEcrecoverRatifier internal ecrecoverRatifier;
    VaultV2Mock internal parentVault;
    IVaultV2 internal realVault;
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
    uint256 internal discountTick = TickLib.priceToTick(0.95e18, DEFAULT_TICK_SPACING);

    function setUp() public virtual {
        vm.setEvmVersion("osaka");
        owner = makeAddr("owner");
        curator = makeAddr("curator");
        (signerAllocator, signerAllocatorPrivateKey) = makeAddrAndKey("signerAllocator");
        privateKey[signerAllocator] = signerAllocatorPrivateKey;

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

        factory = new MidnightAdapterFactory(allDurations);
        adapter = MidnightAdapter(factory.createMidnightAdapter(address(parentVault), address(midnight)));

        ecrecoverRatifier = new MidnightAdapterEcrecoverRatifier();
        addSubRatifier(adapter, address(ecrecoverRatifier));

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
        assertEq(adapter.NO_SELL_CHECK_DELAY(), 3 days, "NO_SELL_CHECK_DELAY");
        skip(100);
        assertEq(adapter.realAssets(), 0, "realAssets after time passes");
    }

    /* TIMELOCKS */

    function testSubmit(address caller) public {
        vm.assume(caller != curator);
        bytes memory data = abi.encodeCall(IMidnightAdapter.setSkimRecipient, (recipient));

        vm.prank(caller);
        vm.expectRevert(IMidnightAdapter.NotAuthorized.selector);
        adapter.submit(data);

        vm.expectEmit(address(adapter));
        emit IMidnightAdapter.Submit(IMidnightAdapter.setSkimRecipient.selector, data, block.timestamp);
        vm.prank(curator);
        adapter.submit(data);
        assertEq(adapter.executableAt(data), block.timestamp, "executableAt");

        vm.prank(curator);
        vm.expectRevert(IMidnightAdapter.DataAlreadyPending.selector);
        adapter.submit(data);
    }

    function testRevoke(address caller) public {
        address sentinel = makeAddr("timelockSentinel");
        stdstore.target(address(parentVault)).sig("isSentinel(address)").with_key(sentinel).checked_write(true);
        vm.assume(caller != curator && !parentVault.isSentinel(caller));
        bytes memory data = abi.encodeCall(IMidnightAdapter.setSkimRecipient, (recipient));

        vm.prank(sentinel);
        vm.expectRevert(IMidnightAdapter.DataNotTimelocked.selector);
        adapter.revoke(data);

        vm.prank(curator);
        adapter.submit(data);

        vm.prank(caller);
        vm.expectRevert(IMidnightAdapter.NotAuthorized.selector);
        adapter.revoke(data);

        uint256 snapshot = vm.snapshotState();
        vm.expectEmit(address(adapter));
        emit IMidnightAdapter.Revoke(curator, IMidnightAdapter.setSkimRecipient.selector, data);
        vm.prank(curator);
        adapter.revoke(data);
        assertEq(adapter.executableAt(data), 0, "revoked by curator");

        vm.revertToStateAndDelete(snapshot);
        vm.expectEmit(address(adapter));
        emit IMidnightAdapter.Revoke(sentinel, IMidnightAdapter.setSkimRecipient.selector, data);
        vm.prank(sentinel);
        adapter.revoke(data);
        assertEq(adapter.executableAt(data), 0, "revoked by sentinel");
    }

    function testIncreaseAndDecreaseTimelock(uint256 oldDuration, uint256 newDuration) public {
        oldDuration = bound(oldDuration, 1, 3650 days);
        newDuration = bound(newDuration, 0, oldDuration);
        bytes4 selector = IMidnightAdapter.setSkimRecipient.selector;

        bytes memory increaseData = abi.encodeCall(IMidnightAdapter.increaseTimelock, (selector, oldDuration));
        vm.prank(curator);
        adapter.submit(increaseData);
        vm.expectEmit(address(adapter));
        emit IMidnightAdapter.Accept(IMidnightAdapter.increaseTimelock.selector, increaseData);
        vm.expectEmit(address(adapter));
        emit IMidnightAdapter.IncreaseTimelock(selector, oldDuration);
        adapter.increaseTimelock(selector, oldDuration);
        assertEq(adapter.timelock(selector), oldDuration, "increased timelock");

        bytes memory invalidIncreaseData =
            abi.encodeCall(IMidnightAdapter.increaseTimelock, (selector, oldDuration - 1));
        vm.prank(curator);
        adapter.submit(invalidIncreaseData);
        vm.expectRevert(IMidnightAdapter.TimelockNotIncreasing.selector);
        adapter.increaseTimelock(selector, oldDuration - 1);

        bytes memory invalidDecreaseData =
            abi.encodeCall(IMidnightAdapter.decreaseTimelock, (selector, oldDuration + 1));
        vm.prank(curator);
        adapter.submit(invalidDecreaseData);
        assertEq(adapter.executableAt(invalidDecreaseData), block.timestamp + oldDuration, "invalid decrease delay");
        skip(oldDuration);
        vm.expectRevert(IMidnightAdapter.TimelockNotDecreasing.selector);
        adapter.decreaseTimelock(selector, oldDuration + 1);

        bytes memory decreaseData = abi.encodeCall(IMidnightAdapter.decreaseTimelock, (selector, newDuration));
        vm.prank(curator);
        adapter.submit(decreaseData);
        assertEq(adapter.executableAt(decreaseData), block.timestamp + oldDuration, "decrease delay");
        skip(oldDuration);
        vm.expectEmit(address(adapter));
        emit IMidnightAdapter.Accept(IMidnightAdapter.decreaseTimelock.selector, decreaseData);
        vm.expectEmit(address(adapter));
        emit IMidnightAdapter.DecreaseTimelock(selector, newDuration);
        adapter.decreaseTimelock(selector, newDuration);
        assertEq(adapter.timelock(selector), newDuration, "decreased timelock");
    }

    function testCannotSetDecreaseTimelock() public {
        bytes4 selector = IMidnightAdapter.decreaseTimelock.selector;
        bytes memory increaseData = abi.encodeCall(IMidnightAdapter.increaseTimelock, (selector, 1 days));
        vm.prank(curator);
        adapter.submit(increaseData);
        vm.expectRevert(IMidnightAdapter.AutomaticallyTimelocked.selector);
        adapter.increaseTimelock(selector, 1 days);

        bytes memory decreaseData = abi.encodeCall(IMidnightAdapter.decreaseTimelock, (selector, 0));
        vm.prank(curator);
        adapter.submit(decreaseData);
        vm.expectRevert(IMidnightAdapter.AutomaticallyTimelocked.selector);
        adapter.decreaseTimelock(selector, 0);

        assertEq(adapter.timelock(selector), 0, "decreaseTimelock timelock");
    }

    function testTimelockedCall(uint256 duration) public {
        duration = bound(duration, 1, 3650 days);
        submitTimelock(IMidnightAdapter.setSkimRecipient.selector, duration);

        bytes memory data = abi.encodeCall(IMidnightAdapter.setSkimRecipient, (recipient));
        vm.prank(curator);
        adapter.submit(data);

        skip(duration - 1);
        vm.expectRevert(IMidnightAdapter.TimelockNotExpired.selector);
        adapter.setSkimRecipient(recipient);

        skip(1);
        vm.expectEmit(address(adapter));
        emit IMidnightAdapter.Accept(IMidnightAdapter.setSkimRecipient.selector, data);
        adapter.setSkimRecipient(recipient);
        assertEq(adapter.skimRecipient(), recipient, "skimRecipient");
        assertEq(adapter.executableAt(data), 0, "executableAt");

        vm.expectRevert(IMidnightAdapter.DataNotTimelocked.selector);
        adapter.setSkimRecipient(recipient);
    }

    function testAbdicate() public {
        bytes4 selector = IMidnightAdapter.setSkimRecipient.selector;
        vm.expectRevert(IMidnightAdapter.DataNotTimelocked.selector);
        adapter.abdicate(selector);

        bytes memory abdicateData = abi.encodeCall(IMidnightAdapter.abdicate, (selector));
        vm.prank(curator);
        adapter.submit(abdicateData);
        vm.expectEmit(address(adapter));
        emit IMidnightAdapter.Accept(IMidnightAdapter.abdicate.selector, abdicateData);
        vm.expectEmit(address(adapter));
        emit IMidnightAdapter.Abdicate(selector);
        adapter.abdicate(selector);
        assertTrue(adapter.abdicated(selector), "abdicated");

        bytes memory data = abi.encodeCall(IMidnightAdapter.setSkimRecipient, (recipient));
        vm.prank(curator);
        adapter.submit(data);
        vm.expectRevert(IMidnightAdapter.Abdicated.selector);
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
        emit IMidnightAdapter.SetMaxSellRate(curator, collateralParamsHash, newMaxSellRate);
        vm.prank(curator);
        adapter.setMaxSellRate(collateralParamsHash, newMaxSellRate);
        assertEq(adapter.maxSellRate(collateralParamsHash), newMaxSellRate, "maximum updated immediately");
    }

    function testSetMaxSellRateNotAuthorized(address caller, bool sentinel) public {
        vm.assume(caller != curator);
        if (sentinel) {
            stdstore.target(address(parentVault)).sig("isSentinel(address)").with_key(caller).checked_write(true);
        }
        vm.expectRevert(IMidnightAdapter.NotAuthorized.selector);
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

    function testSetMinRateNotAuthorized(address caller, uint256 newMinRate) public {
        vm.assume(caller != curator);
        vm.expectRevert(IMidnightAdapter.NotAuthorized.selector);
        vm.prank(caller);
        adapter.setMinRate(newMinRate);
    }

    function testSetMinRateAuthorized(uint256 oldMinRate, uint256 newMinRate) public {
        vm.prank(curator);
        adapter.setMinRate(oldMinRate);
        vm.expectEmit(address(adapter));
        emit IMidnightAdapter.SetMinRate(newMinRate);
        vm.prank(curator);
        adapter.setMinRate(newMinRate);
        assertEq(adapter.minRate(), newMinRate, "minRate");
    }

    function testSetMinRateDecrease(uint256 oldMinRate, uint256 newMinRate) public {
        newMinRate = bound(newMinRate, 0, oldMinRate);
        setMinRate(oldMinRate);
        setMinRate(newMinRate);
        assertEq(adapter.minRate(), newMinRate, "minRate decreased");
    }

    function testMinRateRejectsPreviouslySignedZeroRateOffer() public {
        Offer memory offer = makeBuyOffer(30 days, 1e18, MAX_TICK);
        midnight.supplyCollateral(offer.market, 0, offer.maxUnits, taker);
        bytes memory data = sign([offer], signerAllocator);
        assertEq(adapter.minRate(), 0, "default minRate");
        setMinRate(1);

        vm.prank(taker);
        vm.expectRevert(IMidnightAdapter.RateTooLow.selector);
        midnight.take(offer, data, offer.maxUnits, taker, taker, address(0), "");
        assertEq(adapter.realAssets(), 0, "failed buy leaves no assets");
        assertEq(midnight.consumed(address(adapter), offer.group), 0, "offer not consumed");

        setMinRate(0);
        take(offer);
        assertEq(adapter.netCredit(_marketId(offer.market)), offer.maxUnits, "zero rate accepted");
    }

    function testMinRateBoundary(uint256 duration, uint256 assets, uint256 continuousFee) public {
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
        setMinRate(rate + 1);

        vm.expectRevert(IMidnightAdapter.RateTooLow.selector);
        take(offer);

        setMinRate(rate);
        take(offer);
        assertEq(adapter.netCredit(_marketId(offer.market)), netCredit, "net rate accepted");
    }

    function testMinRateUsesRemainingDuration() public {
        Offer memory offer = makeBuyOffer(30 days, 1e18, discountTick);
        offer.expiry = offer.market.maturity;
        midnight.supplyCollateral(offer.market, 0, offer.maxUnits, taker);
        uint256 paidAssets = uint256(offer.maxUnits).mulDivDown(TickLib.tickToPrice(offer.tick), 1e18);
        uint256 rate = (offer.maxUnits - paidAssets) * 1e18 / (paidAssets * 15 days);
        setMinRate(rate);

        vm.expectRevert(IMidnightAdapter.RateTooLow.selector);
        take(offer);

        skip(15 days);
        take(offer);
        assertEq(adapter.netCredit(_marketId(offer.market)), offer.maxUnits, "remaining duration used");
    }

    function testMinRateZeroPaidAssets() public {
        Offer memory offer = makeBuyOffer(30 days, 1e18, MAX_TICK);
        offer.tick = 0;
        midnight.supplyCollateral(offer.market, 0, offer.maxUnits, taker);
        setMinRate(type(uint256).max);
        uint256 balanceBefore = loanToken.balanceOf(address(parentVault));

        take(offer);

        assertEq(loanToken.balanceOf(address(parentVault)), balanceBefore, "no assets paid");
        assertEq(adapter.netCredit(_marketId(offer.market)), offer.maxUnits, "free credit accepted");
    }

    function testMinRateAtMaturity() public {
        setMinRate(type(uint256).max);
        Offer memory offer = buy(0, 1e18);
        assertEq(adapter.netCredit(_marketId(offer.market)), offer.maxUnits, "matured credit accepted");
    }

    function testMinRateDoesNotRestrictSells() public {
        Offer memory offer = buy(30 days, 1e18);
        setMinRate(type(uint256).max);
        sell(offer.market, offer.maxUnits);
        assertEq(adapter.netCredit(_marketId(offer.market)), 0, "sell accepted");
    }

    /// forge-config: default.isolate = true
    function testMinRateAllocatorTakeRealVault() public {
        setUpRealVault();
        Market memory market = makeBuyOffer(7 days, 1e18, MAX_TICK).market;
        Offer memory offer = makeExternalOffer(market, false, 1e18, MAX_TICK);
        setMinRate(1);

        vm.prank(signerAllocator);
        vm.expectRevert(IMidnightAdapter.RateTooLow.selector);
        adapter.take(offer, "", offer.maxUnits);
        assertEq(realVault.allocation(adapter.adapterId()), 0, "failed buy leaves no allocation");
        assertEq(loanToken.balanceOf(address(realVault)), 10e18, "failed buy leaves vault funds unchanged");

        setMinRate(0);
        vm.prank(signerAllocator);
        adapter.take(offer, "", offer.maxUnits);
        assertEq(realVault.allocation(adapter.adapterId()), 1e18, "buy accepted");
    }

    /// forge-config: default.isolate = true
    function testMinRateAllocatorTakeNetRate() public {
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
        setMinRate(rate + 1);

        vm.prank(signerAllocator);
        vm.expectRevert(IMidnightAdapter.RateTooLow.selector);
        adapter.take(offer, "", offer.maxUnits);

        setMinRate(rate);
        vm.prank(signerAllocator);
        adapter.take(offer, "", offer.maxUnits);
        assertEq(adapter.netCredit(marketId), netCredit, "net rate accepted");
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
        vm.expectRevert(IMidnightAdapter.LoanAssetMismatch.selector);
        adapter.isRatified(offer, data, taker);
    }

    function testRatifyIncorrectMaker(uint256 seed, address otherMaker) public {
        vm.setSeed(seed);
        Offer memory offer = _ratificationSetup();
        vm.assume(otherMaker != address(adapter));
        offer.maker = otherMaker;
        bytes32 _root = root(offer);
        bytes memory data = ratifierData(_root, signerAllocator);
        vm.expectRevert(IMidnightAdapter.IncorrectMaker.selector);
        adapter.isRatified(offer, data, taker);
    }

    function testRatifyOtherAdapterSigner(uint256 seed) public {
        vm.setSeed(seed);
        (address otherAllocator, uint256 otherAllocatorKey) = makeAddrAndKey("otherAllocator");
        privateKey[otherAllocator] = otherAllocatorKey;
        VaultV2Mock otherVault = new VaultV2Mock(address(loanToken), owner, curator, otherAllocator, address(0));
        address otherAdapter = factory.createMidnightAdapter(address(otherVault), address(midnight));
        Offer memory offer = _ratificationSetup();
        offer.maker = otherAdapter;
        bytes32 _root = root(offer);
        vm.expectRevert(IMidnightAdapterEcrecoverRatifier.IncorrectSigner.selector);
        ecrecoverRatifier.isRatified(offer, innerRatifierData(_root, signerAllocator, 0, proof([offer])), taker);
        bytes memory data = innerRatifierData(_root, otherAllocator, 0, proof([offer]));
        assertEq(ecrecoverRatifier.isRatified(offer, data, taker), CALLBACK_SUCCESS);
    }

    function testRatifyIncorrectCallbackAddress(uint256 seed) public {
        vm.setSeed(seed);
        Offer memory offer = _ratificationSetup();
        offer.callback = address(0);
        bytes32 _root = root(offer);
        bytes memory data = ratifierData(_root, signerAllocator);
        vm.expectRevert(IMidnightAdapter.IncorrectCallbackAddress.selector);
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
        siblingProof[0] = HashLib.hashOffer(offer);
        data = ratifierData(_root, signerAllocator, 1, siblingProof);
        assertEq(adapter.isRatified(sibling, data, taker), CALLBACK_SUCCESS, "second leaf");

        data = ratifierData(_root, signerAllocator, 0, siblingProof);
        vm.expectRevert(IMidnightAdapterEcrecoverRatifier.InvalidProof.selector);
        adapter.isRatified(sibling, data, taker);
    }

    function testRatifyInvalidProof(uint256 seed) public {
        vm.setSeed(seed);
        Offer memory offer = _ratificationSetup();
        bytes32 wrongRoot = keccak256("wrong root");
        bytes32[] memory emptyProof = new bytes32[](0);
        bytes memory data = ratifierData(wrongRoot, signerAllocator, 0, emptyProof);
        vm.expectRevert(IMidnightAdapterEcrecoverRatifier.InvalidProof.selector);
        adapter.isRatified(offer, data, taker);
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
        vm.expectRevert(IMidnightAdapterEcrecoverRatifier.IncorrectSigner.selector);
        adapter.isRatified(offer, data, taker);
    }

    function testRatifySellOfferWithoutReduceOnly(uint256 seed) public {
        vm.setSeed(seed);
        Offer memory offer = _ratificationSetup();
        offer.buy = false;
        offer.reduceOnly = false;
        bytes32 _root = HashLib.hashOffer(offer);
        bytes memory data = ratifierData(_root, signerAllocator);
        assertEq(adapter.isRatified(offer, data, taker), CALLBACK_SUCCESS, "callback success");
    }

    function testRatifyReduceOnlySellAccepted(uint256 seed) public {
        vm.setSeed(seed);
        Offer memory offer = _ratificationSetup();
        offer.buy = false;
        offer.reduceOnly = true;
        bytes32 _root = HashLib.hashOffer(offer);
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
        vm.expectRevert(IMidnightAdapter.IncorrectReceiver.selector);
        adapter.isRatified(offer, data, taker);
    }

    function testCancelRootByAllocator(uint256 seed) public {
        vm.setSeed(seed);
        Offer memory offer = _ratificationSetup();
        bytes32 _root = root(offer);
        bytes memory data = ratifierData(_root, signerAllocator);
        assertEq(adapter.isRatified(offer, data, taker), CALLBACK_SUCCESS, "ratifies before cancel");
        vm.expectEmit(address(ecrecoverRatifier));
        emit IMidnightAdapterEcrecoverRatifier.CancelRoot(signerAllocator, address(adapter), _root);
        vm.prank(signerAllocator);
        ecrecoverRatifier.cancelRoot(address(adapter), _root);
        assertTrue(ecrecoverRatifier.isRootCanceled(address(adapter), _root), "root canceled");
        vm.expectRevert(IMidnightAdapterEcrecoverRatifier.RootCanceled.selector);
        adapter.isRatified(offer, data, taker);
    }

    function testCancelRootBySentinel(uint256 seed, address sentinel) public {
        vm.setSeed(seed);
        vm.assume(sentinel != signerAllocator);
        stdstore.target(address(parentVault)).sig("isSentinel(address)").with_key(sentinel).checked_write(true);
        Offer memory offer = _ratificationSetup();
        bytes32 _root = root(offer);
        bytes memory data = ratifierData(_root, signerAllocator);
        vm.prank(sentinel);
        ecrecoverRatifier.cancelRoot(address(adapter), _root);
        assertTrue(ecrecoverRatifier.isRootCanceled(address(adapter), _root), "root canceled");
        vm.expectRevert(IMidnightAdapterEcrecoverRatifier.RootCanceled.selector);
        adapter.isRatified(offer, data, taker);
    }

    function testCancelRootUnauthorized(address caller) public {
        vm.assume(!parentVault.isAllocator(caller) && !parentVault.isSentinel(caller));
        vm.prank(caller);
        vm.expectRevert(IMidnightAdapterEcrecoverRatifier.NotAuthorized.selector);
        ecrecoverRatifier.cancelRoot(address(adapter), keccak256("some root"));
    }

    function testAddSubRatifierNotTimelocked(address caller, address subRatifier) public {
        vm.prank(caller);
        vm.expectRevert(IMidnightAdapter.DataNotTimelocked.selector);
        adapter.addSubRatifier(subRatifier);
    }

    function testRemoveSubRatifierUnauthorized(address caller, address subRatifier) public {
        vm.assume(!parentVault.isAllocator(caller) && !parentVault.isSentinel(caller));
        vm.prank(caller);
        vm.expectRevert(IMidnightAdapter.NotAuthorized.selector);
        adapter.removeSubRatifier(subRatifier);
    }

    function testAddAndRemoveSubRatifier(address subRatifier) public {
        vm.prank(curator);
        adapter.submit(abi.encodeCall(IMidnightAdapter.addSubRatifier, (subRatifier)));
        vm.expectEmit(address(adapter));
        emit IMidnightAdapter.AddSubRatifier(subRatifier);
        adapter.addSubRatifier(subRatifier);
        assertTrue(adapter.isSubRatifier(subRatifier), "authorized");
        vm.expectEmit(address(adapter));
        emit IMidnightAdapter.RemoveSubRatifier(signerAllocator, subRatifier);
        vm.prank(signerAllocator);
        adapter.removeSubRatifier(subRatifier);
        assertFalse(adapter.isSubRatifier(subRatifier), "unauthorized");
    }

    function testSentinelCanRemoveSubRatifier(address sentinel) public {
        vm.assume(sentinel != signerAllocator);
        stdstore.target(address(parentVault)).sig("isSentinel(address)").with_key(sentinel).checked_write(true);
        vm.prank(sentinel);
        adapter.removeSubRatifier(address(ecrecoverRatifier));
        assertFalse(adapter.isSubRatifier(address(ecrecoverRatifier)), "removed by sentinel");
    }

    function testRatifySubRatifierFailed(uint256 seed, address subRatifier) public {
        vm.setSeed(seed);
        vm.assume(!adapter.isSubRatifier(subRatifier));
        Offer memory offer = _ratificationSetup();
        vm.expectRevert(IMidnightAdapter.SubRatifierFailed.selector);
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
        vm.expectRevert(IMidnightAdapter.IncorrectReceiver.selector);
        midnight.take(offer, rogueData, offer.maxUnits, taker, address(0), address(0), "");
        offer.receiverIfMakerIsSeller = address(adapter);

        offer.callback = address(0);
        vm.prank(taker);
        vm.expectRevert(IMidnightAdapter.IncorrectCallbackAddress.selector);
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
        bytes memory data = sign([offer], signerAllocator);

        vm.prank(signerAllocator);
        adapter.removeSubRatifier(address(ecrecoverRatifier));
        vm.prank(taker);
        vm.expectRevert(IMidnightAdapter.SubRatifierFailed.selector);
        midnight.take(offer, data, offer.maxUnits, taker, taker, address(0), "");

        addSubRatifier(adapter, address(ecrecoverRatifier));
        vm.prank(taker);
        midnight.take(offer, data, offer.maxUnits, taker, taker, address(0), "");
        assertGt(adapter.realAssets(), 0, "position opened");
    }

    function testRemovedAllocatorSignatureRejected() public {
        Offer memory offer = makeBuyOffer(30 days, 1e18, discountTick);
        midnight.supplyCollateral(offer.market, 0, offer.maxUnits, taker);
        midnight.supplyCollateral(offer.market, 1, offer.maxUnits, taker);
        bytes memory data = sign([offer], signerAllocator);

        stdstore.target(address(parentVault)).sig("isAllocator(address)").with_key(signerAllocator).checked_write(false);
        vm.prank(taker);
        vm.expectRevert(IMidnightAdapterEcrecoverRatifier.IncorrectSigner.selector);
        midnight.take(offer, data, offer.maxUnits, taker, taker, address(0), "");
    }

    function testSharedRatifierTwoAdapters() public {
        (address otherAllocator, uint256 otherAllocatorKey) = makeAddrAndKey("otherAllocator");
        privateKey[otherAllocator] = otherAllocatorKey;
        VaultV2Mock otherVault = new VaultV2Mock(address(loanToken), owner, curator, otherAllocator, address(0));
        IMidnightAdapter otherAdapter =
            IMidnightAdapter(factory.createMidnightAdapter(address(otherVault), address(midnight)));
        addSubRatifier(otherAdapter, address(ecrecoverRatifier));
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
        vm.expectRevert(IMidnightAdapterEcrecoverRatifier.NotAuthorized.selector);
        ecrecoverRatifier.cancelRoot(address(otherAdapter), root(offerB));

        // Canceling A's root value on B does not affect A.
        vm.prank(otherAllocator);
        ecrecoverRatifier.cancelRoot(address(otherAdapter), root(offerA));
        vm.prank(taker);
        midnight.take(offerA, sign([offerA], signerAllocator), offerA.maxUnits, taker, taker, address(0), "");
        assertGt(adapter.realAssets(), 0, "A position opened");

        // B takes with its own allocator through the same ratifier deployment.
        vm.prank(taker);
        midnight.take(
            offerB,
            ratifierData(root(offerB), otherAllocator, 0, proof([offerB])),
            offerB.maxUnits,
            taker,
            taker,
            address(0),
            ""
        );
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

    function testRatifyWrongDomain(uint256 seed) public {
        vm.setSeed(seed);
        Offer memory offer = _ratificationSetup();
        bytes32 _root = root(offer);
        bytes32 structHash = keccak256(abi.encode(HashLib.offerTreeTypeHash(0), _root));
        bytes32 domainSeparator = keccak256(abi.encode(EIP712_DOMAIN_TYPEHASH, block.chainid, address(adapter)));
        bytes32 digest = keccak256(bytes.concat("\x19\x01", domainSeparator, structHash));
        (uint8 v, bytes32 r, bytes32 vs) = vm.sign(signerAllocatorPrivateKey, digest);
        bytes memory data = abi.encode(
            address(ecrecoverRatifier), abi.encode(Signature({v: v, r: r, s: vs}), _root, uint256(0), new bytes32[](0))
        );
        vm.expectRevert(IMidnightAdapterEcrecoverRatifier.IncorrectSigner.selector);
        adapter.isRatified(offer, data, taker);
    }

    function testRatifyChainIdChanged(uint256 seed) public {
        vm.setSeed(seed);
        Offer memory offer = _ratificationSetup();
        bytes memory data = ratifierData(root(offer), signerAllocator);
        assertEq(adapter.isRatified(offer, data, taker), CALLBACK_SUCCESS, "valid before fork");
        vm.chainId(block.chainid + 1);
        vm.expectRevert(IMidnightAdapterEcrecoverRatifier.IncorrectSigner.selector);
        adapter.isRatified(offer, data, taker);
    }

    function testRatifyInvalidSignature(uint256 seed) public {
        vm.setSeed(seed);
        Offer memory offer = _ratificationSetup();
        bytes32 _root = root(offer);
        Signature memory sig = Signature({v: 17, r: bytes32(vm.randomUint()), s: bytes32(vm.randomUint())});
        bytes memory data = abi.encode(address(ecrecoverRatifier), abi.encode(sig, _root, uint256(0), new bytes32[](0)));
        vm.expectRevert(IMidnightAdapterEcrecoverRatifier.IncorrectSigner.selector);
        adapter.isRatified(offer, data, taker);
    }

    /* FACTORY */

    function testFactoryCreateMidnightAdapter() public {
        VaultV2Mock newVault = new VaultV2Mock(address(loanToken), owner, curator, signerAllocator, address(0));

        vm.expectEmit(true, true, false, false, address(factory));
        emit IMidnightAdapterFactory.CreateMidnightAdapter(address(newVault), address(midnight), address(0));
        address newAdapter = factory.createMidnightAdapter(address(newVault), address(midnight));

        assertEq(factory.midnightAdapter(address(newVault), address(midnight)), newAdapter, "midnightAdapter");
        assertTrue(factory.isMidnightAdapter(newAdapter), "isMidnightAdapter");
        assertEq(IMidnightAdapter(newAdapter).parentVault(), address(newVault), "parentVault");
        assertEq(IMidnightAdapter(newAdapter).midnight(), address(midnight), "midnight");
        assertEq(IMidnightAdapter(newAdapter).durations(), allDurations, "durations");
        assertTrue(midnight.isAuthorized(newAdapter, newAdapter), "adapter is its own ratifier");

        // Fixed salt: one adapter per (vault, midnight) pair.
        vm.expectRevert();
        factory.createMidnightAdapter(address(newVault), address(midnight));
    }

    /* DURATIONS */

    function testConstructorGetters() public view {
        assertEq(adapter.asset(), address(loanToken), "asset");
        assertEq(adapter.parentVault(), address(parentVault), "parentVault");
        assertEq(adapter.midnight(), address(midnight), "midnight");
        assertEq(adapter.skimRecipient(), address(0), "skimRecipient");
        assertEq(adapter.durationsLength(), allDurations.length, "durationsLength");
        bytes32 expectedPackedDurations;
        for (uint256 i = 0; i < allDurations.length; i++) {
            expectedPackedDurations |= bytes32(allDurations[i] << (32 * i));
        }
        assertEq(adapter.packedDurations(), expectedPackedDurations, "packedDurations");
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
        assertEq(ids[1], keccak256(abi.encode("marketConfig", enterGate, liquidatorGate, rcfThreshold)));
        for (uint256 i = 0; i < market.collateralParams.length; i++) {
            assertEq(ids[i * 2 + 2], keccak256(abi.encode("collateralToken", market.collateralParams[i].token)));
            assertEq(
                ids[i * 2 + 3],
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

        // Duration ids come from the stored duration count: none for a maturity that was never bought.
        assertEq(ids.length, 2 + market.collateralParams.length * 2);
    }

    function testIdsDurations(uint256 durationIndex, uint256 elapsed) public {
        durationIndex = bound(durationIndex, 0, allDurations.length - 1);
        uint256 duration = allDurations[durationIndex];
        elapsed = bound(elapsed, 0, duration);
        Offer memory offer = buy(duration, 1e18);
        uint256 fixedIds = 2 + offer.market.collateralParams.length * 2;

        skip(elapsed);
        bytes32[] memory ids = adapter.ids(offer.market);
        assertEq(ids.length, fixedIds + durationIndex + 1, "stale until updated");
        for (uint256 i = 0; i <= durationIndex; i++) {
            assertEq(ids[fixedIds + i], durationId(allDurations[i]), "duration id");
        }

        adapter.updateDurationCaps(offer.market.maturity);
        uint256 count = 0;
        while (count < allDurations.length && duration - elapsed >= allDurations[count]) count++;
        assertEq(adapter.ids(offer.market).length, fixedIds + count, "updated");
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

        bytes memory idData =
            abi.encode("marketConfig", offer.market.enterGate, offer.market.liquidatorGate, offer.market.rcfThreshold);
        bytes memory data = sign([offer], signerAllocator);
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
        assertEq(realVault.allocation(keccak256(idData)), 1e18, "market config allocation after buy");

        sellUnits(offer.market, 1e18, MAX_TICK);
        assertEq(realVault.allocation(keccak256(idData)), 0, "market config allocation after sell");
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
        timeToMaturity = bound(timeToMaturity, duration, 100 * 365 days);
        extraSkip = bound(extraSkip, 1, 10 * 365 days);

        Offer memory offer = buy(timeToMaturity, 1e18);
        assertEq(parentVault.allocation(durationId(duration)), 1e18);

        skip(timeToMaturity - duration + extraSkip);

        adapter.updateDurationCaps(offer.market.maturity);

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
        adapter.updateDurationCaps(offer.market.maturity);
        uint256 savedAllocation = parentVault.allocation(durationId(duration));
        adapter.updateDurationCaps(offer.market.maturity);
        assertEq(parentVault.allocation(durationId(duration)), savedAllocation);
    }

    function testWithdrawThenUpdateDurationCaps() public {
        Offer memory offer = buy(7 days, 1e18);
        assertEq(parentVault.allocation(durationId(1 days)), 1e18, "1 day, before");
        assertEq(parentVault.allocation(durationId(7 days)), 1e18, "7 days, before");

        skip(7 days);

        vm.prank(taker);
        midnight.repay(offer.market, 1e18, taker, address(0), "");
        vm.prank(signerAllocator);
        adapter.withdrawToVault(offer.market, 0.5e18);

        assertEq(parentVault.allocation(durationId(1 days)), 0.5e18, "1 day, stale");
        assertEq(parentVault.allocation(durationId(7 days)), 0.5e18, "7 days, stale");

        adapter.updateDurationCaps(offer.market.maturity);

        assertEq(parentVault.allocation(durationId(1 days)), 0, "1 day");
        assertEq(parentVault.allocation(durationId(7 days)), 0, "7 days");
    }

    function testSellThenUpdateDurationCaps() public {
        Offer memory offer = buy(7 days, 1e18);
        assertEq(parentVault.allocation(durationId(1 days)), 1e18, "1 day, before");
        assertEq(parentVault.allocation(durationId(7 days)), 1e18, "7 days, before");

        skip(1);

        parentVault.setTotalAssets(1e18);
        vm.expectEmit(address(adapter));
        emit IMidnightAdapter.Sell(_marketId(offer.market), 0.5e18, 0.5e18);
        sell(offer.market, 0.5e18);

        assertEq(parentVault.allocation(durationId(1 days)), 0.5e18, "1 day, stale");
        assertEq(parentVault.allocation(durationId(7 days)), 0.5e18, "7 days, stale");

        adapter.updateDurationCaps(offer.market.maturity);

        assertEq(parentVault.allocation(durationId(1 days)), 0.5e18, "1 day");
        assertEq(parentVault.allocation(durationId(7 days)), 0, "7 days");
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
        emit IMidnightAdapter.Buy(marketId, 1e18, 1e18, 1e18);
        take(offer);

        uint128 netCredit = adapter.netCredit(marketId);
        assertEq(netCredit, 1e18, "netCredit");
        assertEq(adapter.realAssets(), 3e18, "realAssets");
        assertMarkets([_marketId(first.market), marketId, _marketId(last.market)]);
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
        emit IMidnightAdapter.UpdateMarket(_marketId(soldOffer.market), 0, 0);
        sell(soldOffer.market, 1e18);

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

        assertEq(adapter.netCredit(marketId), 0.5e18, "synchronized without refetching the market");
    }

    function testForceDeallocateThenUpdateDurationCaps() public {
        Offer memory offer = buy(7 days, 1e18);
        assertEq(parentVault.allocation(durationId(1 days)), 1e18, "1 day, before");
        assertEq(parentVault.allocation(durationId(7 days)), 1e18, "7 days, before");

        skip(1);

        forceDeallocate(offer.market, 0.5e18);

        assertEq(parentVault.allocation(durationId(1 days)), 0.5e18, "1 day, stale");
        assertEq(parentVault.allocation(durationId(7 days)), 0.5e18, "7 days, stale");

        adapter.updateDurationCaps(offer.market.maturity);

        assertEq(parentVault.allocation(durationId(1 days)), 0.5e18, "1 day");
        assertEq(parentVault.allocation(durationId(7 days)), 0, "7 days");
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
        vm.expectRevert(IMidnightAdapter.TooManyMarkets.selector);
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
        stdstore.target(address(midnight))
            .sig("credit(bytes32,address)")
            .with_key(marketId)
            .with_key(address(adapter))
            .checked_write(units - loss);

        offer.group = bytes32("second");
        midnight.supplyCollateral(offer.market, 0, units, taker);
        midnight.supplyCollateral(offer.market, 1, units, taker);
        take(offer);

        assertEq(adapter.maturities(offer.market.maturity).netCredit, 2 * units - loss);
        uint256 expectedValue = 2 * units - loss - (2 * units - loss).mulDivUp(growth * duration, 1e18);
        assertEq(adapter.realAssets(), expectedValue);
        uint128 marketNetCredit = adapter.netCredit(marketId);
        assertEq(marketNetCredit, 2 * units - loss);
    }

    function testOnSellMaxSellRate() public {
        uint256 price = TickLib.tickToPrice(MAX_TICK - 4);
        uint256 maxSellRate = (1e18 - price).mulDivUp(1e18, price * 30 days);

        deal(address(loanToken), address(parentVault), 1e18);
        Offer memory offer = buy(30 days, 1e18);
        setMaxSellRate(offer.market, maxSellRate);

        sellUnits(offer.market, 1e18, MAX_TICK - 4);

        uint128 marketNetCredit = adapter.netCredit(_marketId(offer.market));
        assertEq(marketNetCredit, 0);
        assertEq(adapter.realAssets(), 0);
        assertEq(adapter.maxSellRate(keccak256(abi.encode(offer.market.collateralParams))), maxSellRate);
    }

    // Same maximum rate, reached through the allocator take path: taking a buy offer makes the adapter sell.
    function testTakeMaxSellRate() public {
        uint256 price = TickLib.tickToPrice(MAX_TICK - 4);
        uint256 maxSellRate = (1e18 - price).mulDivUp(1e18, price * 30 days);

        deal(address(loanToken), address(parentVault), 1e18);
        Offer memory offer = buy(30 days, 1e18);
        setMaxSellRate(offer.market, maxSellRate);

        Offer memory buyOffer = makeExternalOffer(offer.market, true, 1e18, MAX_TICK - 4);
        vm.prank(signerAllocator);
        adapter.take(buyOffer, "", 1e18);

        uint128 marketNetCredit = adapter.netCredit(_marketId(offer.market));
        assertEq(marketNetCredit, 0);
        assertEq(adapter.realAssets(), 0);
    }

    function testTakeRoundingShortfallFailsMaxSellRate() public {
        deal(address(loanToken), address(parentVault), 10);
        Offer memory offer = buy(30 days, 10, discountTick);
        assertEq(adapter.netCredit(_marketId(offer.market)), 10);
        assertEq(adapter.realAssets(), 9);
        parentVault.setTotalAssets(10);

        Offer memory buyOffer = makeExternalOffer(offer.market, true, 5, discountTick);
        uint256 maxSellRate = uint256(1e18).mulDivUp(1, 4 * 30 days);
        setMaxSellRate(offer.market, maxSellRate - 1);
        vm.expectRevert(IMidnightAdapter.SellRateTooHigh.selector);
        vm.prank(signerAllocator);
        adapter.take(buyOffer, "", 5);

        setMaxSellRate(offer.market, maxSellRate);
        vm.prank(signerAllocator);
        adapter.take(buyOffer, "", 5);

        assertEq(adapter.netCredit(_marketId(offer.market)), 5);
        assertEq(adapter.realAssets(), 4);
        assertEq(loanToken.balanceOf(address(parentVault)), 5);
    }

    function testMaxSellRateUsesNetCreditAndNetProceeds(bool takerSale) public {
        midnight.setDefaultContinuousFee(address(loanToken), MAX_CONTINUOUS_FEE);
        for (uint256 i = 0; i <= 6; i++) {
            midnight.setDefaultSettlementFee(address(loanToken), i, 10 * CBP);
        }
        Offer memory boughtOffer = buy(30 days, 1e18, discountTick);
        bytes32 marketId = _marketId(boughtOffer.market);
        uint256 soldCredit = boughtOffer.maxUnits;
        uint256 soldNetCredit = adapter.netCredit(marketId);
        uint256 sellerPrice = TickLib.tickToPrice(discountTick) - (takerSale ? 10 * CBP : 0);
        uint256 sellerAssets =
            takerSale ? soldCredit.mulDivDown(sellerPrice, 1e18) : soldCredit.mulDivUp(sellerPrice, 1e18);
        uint256 maxSellRate = (soldNetCredit - sellerAssets).mulDivUp(1e18, sellerAssets * 30 days);
        assertLt(soldNetCredit, soldCredit, "pending continuous fee released on sale");
        assertLt(
            maxSellRate, (soldCredit - sellerAssets).mulDivUp(1e18, sellerAssets * 30 days), "net rate below gross rate"
        );
        Offer memory offer = takerSale
            ? makeExternalOffer(boughtOffer.market, true, 1e18, discountTick)
            : makeSellOffer(boughtOffer.market, soldCredit, discountTick);
        deal(address(loanToken), taker, 2e18);
        uint256 vaultBalanceBefore = loanToken.balanceOf(address(parentVault));
        setMaxSellRate(offer.market, maxSellRate - 1);

        vm.expectRevert(IMidnightAdapter.SellRateTooHigh.selector);
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

        assertEq(adapter.netCredit(marketId), 0, "position sold");
        assertEq(loanToken.balanceOf(address(parentVault)), vaultBalanceBefore + sellerAssets, "net proceeds");
        assertEq(
            adapter.maxSellRate(keccak256(abi.encode(offer.market.collateralParams))),
            maxSellRate,
            "maximum not consumed"
        );
    }

    function testMaxSellRateSharedAcrossMaturitiesAndNotConsumed() public {
        Offer memory first = buy(2 days, 2e18);
        Offer memory second = buy(1 days, 1e18);
        uint256 maxSellRate = uint256(1e18).mulDivUp(1, 2 days);
        setMaxSellRate(first.market, maxSellRate);

        sellUnits(first.market, 1e18, MAX_TICK / 2);
        sellUnits(first.market, 1e18, MAX_TICK / 2);
        vm.expectRevert(IMidnightAdapter.SellRateTooHigh.selector);
        sellUnits(second.market, 1e18, MAX_TICK / 2);

        assertEq(adapter.netCredit(_marketId(first.market)), 0, "both sales accepted");
        assertEq(
            adapter.maxSellRate(keccak256(abi.encode(first.market.collateralParams))),
            maxSellRate,
            "maximum not consumed"
        );
        assertEq(adapter.netCredit(_marketId(second.market)), 1e18, "other market protected");
        setMaxSellRate(second.market, uint256(1e18).mulDivUp(1, 1 days));
        sellUnits(second.market, 1e18, MAX_TICK / 2);
        assertEq(adapter.netCredit(_marketId(second.market)), 0, "shared maximum updated");
    }

    function testMaxSellRateIsPerCollateralParams() public {
        Offer memory first = buy(1 days, 1e18);
        Offer memory second = makeBuyOffer(1 days, 1e18, MAX_TICK);
        second.market.collateralParams = storedSingleCollateral;
        second.group = bytes32("other collaterals");
        midnight.supplyCollateral(second.market, 0, second.maxUnits, taker);
        take(second);
        setMaxSellRate(first.market, 1);
        setMaxSellRate(second.market, uint256(1e18).mulDivUp(1, 1 days));

        sellUnits(second.market, 1e18, MAX_TICK / 2);
        vm.expectRevert(IMidnightAdapter.SellRateTooHigh.selector);
        sellUnits(first.market, 1e18, MAX_TICK / 2);

        assertEq(adapter.netCredit(_marketId(second.market)), 0, "other collateral array sold");
        assertEq(adapter.netCredit(_marketId(first.market)), 1e18, "original collateral array protected");
    }

    function testMaxSellRateBoundary(uint256 duration, uint256 assets, bool unlimitedRate) public {
        duration = bound(duration, 1, 365 days);
        assets = bound(assets, MIN_TEST_ASSETS, MAX_TEST_ASSETS);
        Offer memory offer = buy(duration, assets);
        uint256 sellerAssets = assets.mulDivUp(0.5e18, 1e18);
        uint256 rate = (assets - sellerAssets).mulDivUp(1e18, sellerAssets * duration);
        setMaxSellRate(offer.market, rate - 1);

        vm.expectRevert(IMidnightAdapter.SellRateTooHigh.selector);
        sellUnits(offer.market, assets, MAX_TICK / 2);

        setMaxSellRate(offer.market, unlimitedRate ? type(uint256).max : rate);
        sellUnits(offer.market, assets, MAX_TICK / 2);
        assertEq(adapter.netCredit(_marketId(offer.market)), 0, "rate accepted");
    }

    function testMaxSellRateUsesRemainingDuration() public {
        Offer memory offer = buy(30 days, 2e18);
        setMaxSellRate(offer.market, uint256(1e18).mulDivUp(1, 30 days));
        sellUnits(offer.market, 1e18, MAX_TICK / 2);

        skip(15 days);
        vm.expectRevert(IMidnightAdapter.SellRateTooHigh.selector);
        sellUnits(offer.market, 1e18, MAX_TICK / 2);

        setMaxSellRate(offer.market, uint256(1e18).mulDivUp(1, 15 days));
        sellUnits(offer.market, 1e18, MAX_TICK / 2);
        assertEq(adapter.netCredit(_marketId(offer.market)), 0, "remaining duration used");
    }

    function testMaxSellRateZeroPreventsBelowParSales(bool initiallySet, bool zeroProceeds, uint256 elapsed) public {
        Offer memory offer = buy(30 days, 1e18);
        uint256 tick = zeroProceeds ? 0 : MAX_TICK / 2;
        if (initiallySet) {
            setMaxSellRate(offer.market, 1);
            if (zeroProceeds) vm.expectRevert(stdError.arithmeticError);
            else vm.expectRevert(IMidnightAdapter.SellRateTooHigh.selector);
            sellUnits(offer.market, 1e18, tick);
            setMaxSellRate(offer.market, 0);
        }

        skip(bound(elapsed, 0, 31 days));
        if (zeroProceeds || block.timestamp >= offer.market.maturity) vm.expectRevert(stdError.arithmeticError);
        else vm.expectRevert(IMidnightAdapter.SellRateTooHigh.selector);
        sellUnits(offer.market, 1e18, tick);
        assertEq(adapter.netCredit(_marketId(offer.market)), 1e18, "zero prevents below-par sales");
    }

    function testMaxSellRateAtMaturity(bool afterMaturity, bool zeroRate) public {
        Offer memory offer = buy(30 days, 1e18);
        setMaxSellRate(offer.market, zeroRate ? 0 : 1);
        skip(30 days + (afterMaturity ? 1 : 0));

        vm.expectRevert(stdError.arithmeticError);
        sellUnits(offer.market, 1e18, MAX_TICK / 2);
        assertEq(adapter.netCredit(_marketId(offer.market)), 1e18, "below-par sale rejected");

        sellUnits(offer.market, 1e18, MAX_TICK);
        assertEq(adapter.netCredit(_marketId(offer.market)), 0, "par sale accepted");
    }

    function testMaxSellRateDisabledThreeDaysAfterMaturity(bool takerSale, bool zeroProceeds, uint256 elapsed) public {
        Offer memory boughtOffer = buy(30 days, 1e18);
        skip(30 days + bound(elapsed, adapter.NO_SELL_CHECK_DELAY(), 365 days));
        uint256 tick = zeroProceeds ? 0 : MAX_TICK / 2;
        uint256 vaultBalanceBefore = loanToken.balanceOf(address(parentVault));

        if (takerSale) {
            Offer memory offer = makeExternalOffer(boughtOffer.market, true, 1e18, MAX_TICK);
            offer.tick = tick;
            vm.prank(signerAllocator);
            adapter.take(offer, "", 1e18);
        } else {
            sellUnits(boughtOffer.market, 1e18, tick);
        }

        assertEq(adapter.netCredit(_marketId(boughtOffer.market)), 0, "position sold");
        assertEq(adapter.marketIdsLength(), 0, "market removed");
        assertEq(
            loanToken.balanceOf(address(parentVault)), vaultBalanceBefore + TickLib.tickToPrice(tick), "sale proceeds"
        );
    }

    function testMaxSellRateAllowsParAndNetPremium(bool continuousFee) public {
        if (continuousFee) midnight.setDefaultContinuousFee(address(loanToken), MAX_CONTINUOUS_FEE);
        Offer memory offer = buy(30 days, 1e18, discountTick);
        setMaxSellRate(offer.market, 0);
        deal(address(loanToken), taker, offer.maxUnits);

        sellUnits(offer.market, offer.maxUnits, MAX_TICK);
        assertEq(adapter.netCredit(_marketId(offer.market)), 0, "nonpositive rate accepted");
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
        assertEq(adapter.netCredit(marketId), 0, "position sold");
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
        assertEq(adapter.netCredit(marketId), 0, "position sold");
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

        if (!continuousFee) vm.expectRevert(IMidnightAdapter.SellRateTooHigh.selector);
        vm.prank(signerAllocator);
        adapter.take(offer, "", boughtOffer.maxUnits);

        assertEq(adapter.netCredit(_marketId(offer.market)), continuousFee ? 0 : boughtOffer.maxUnits);
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

        uint128 netCreditA = adapter.netCredit(_marketId(offerA.market));
        uint128 netCreditB = adapter.netCredit(_marketId(offerB.market));
        assertEq(netCreditA, assetsA, "netCredit A");
        assertEq(netCreditB, assetsB, "netCredit B");
        assertEq(adapter.maturities(block.timestamp).netCredit, assetsA + assetsB, "shared netCredit");
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

    function testUpdateMarketOnBuy() public {
        Offer memory offer = makeBuyOffer(7 days, 1e18, MAX_TICK);
        midnight.supplyCollateral(offer.market, 0, offer.maxUnits, taker);
        midnight.supplyCollateral(offer.market, 1, offer.maxUnits, taker);
        vm.expectEmit(address(adapter));
        emit IMidnightAdapter.UpdateMarket(_marketId(offer.market), 1e18, 0);
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

        vm.expectEmit(address(adapter));
        emit IMidnightAdapter.UpdateMarket(_marketId(offer.market), offer.maxUnits, growth);
        vm.prank(signerAllocator);
        adapter.withdrawToVault(offer.market, 0);
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
        vm.expectRevert(IMidnightAdapter.SellRateTooHigh.selector);
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
        vm.expectRevert(IMidnightAdapter.SellRateTooHigh.selector);
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
        uint128 netCredit = adapter.netCredit(marketId);
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
        stdstore.enable_packed_slots()
            .target(address(midnight))
            .sig("pendingFee(bytes32,address)")
            .with_key(marketId)
            .with_key(address(adapter))
            .checked_write(pendingFee);
        stdstore.enable_packed_slots()
            .target(address(midnight))
            .sig("lastLossFactor(bytes32,address)")
            .with_key(marketId)
            .with_key(address(adapter))
            .checked_write(lastLossFactor);
        stdstore.enable_packed_slots()
            .target(address(midnight))
            .sig("lossFactor(bytes32)")
            .with_key(marketId)
            .checked_write(lossFactor);

        skip(elapsed);
        (uint128 expectedCredit, uint128 expectedPendingFee,) =
            midnight.updatePositionView(offer.market, marketId, address(adapter));
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
        uint128 netCredit = adapter.netCredit(_marketId(offer.market));
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
        uint128 netCreditBefore = adapter.netCredit(marketId);
        uint256 paid = vaultBalanceBefore - loanToken.balanceOf(address(parentVault));
        uint256 growth = (netCreditBefore - paid) * 1e18 / (uint256(netCreditBefore) * 30 days);
        skip(15 days);

        OracleMock(storedCollaterals[0].oracle).setPrice(ORACLE_PRICE_SCALE / 4);
        OracleMock(storedCollaterals[1].oracle).setPrice(ORACLE_PRICE_SCALE / 4);
        midnight.liquidate(offer.market, 0, 0, 0, taker, false, address(this), address(0), "");

        (uint128 credit, uint128 pendingFee,) = midnight.updatePositionView(offer.market, marketId, address(adapter));
        uint256 expectedValue = credit - pendingFee - uint256(credit - pendingFee).mulDivUp(growth * 15 days, 1e18);
        assertLt(credit - pendingFee, netCreditBefore, "loss realized");
        assertEq(adapter.realAssets(), expectedValue, "exact loss-adjusted amortized value");
        assertEq(adapter.netCredit(marketId), netCreditBefore, "view does not update the cache");

        midnight.updatePosition(offer.market, address(adapter));
        assertEq(adapter.realAssets(), expectedValue, "permissionless position update");

        vm.expectEmit(address(adapter));
        emit IMidnightAdapter.UpdateMarket(marketId, credit - pendingFee, growth);
        vm.prank(signerAllocator);
        adapter.withdrawToVault(offer.market, 0);
        vm.mockCallRevert(address(midnight), abi.encodeCall(IMidnight.toMarket, (marketId)), "position read");
        assertEq(adapter.realAssets(), expectedValue, "cached after synchronization");

        vm.record();
        assertEq(adapter.netCredit(marketId), credit - pendingFee, "netCredit");
        (bytes32[] memory reads,) = vm.accesses(address(adapter));
        assertEq(reads.length, 1, "one cache slot");
        uint256 packed = uint256(vm.load(address(adapter), reads[0]));
        assertEq(uint128(packed), credit - pendingFee, "packed net credit");
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
        assertEq(adapter.netCredit(marketId), offer.maxUnits, "cap accounting not updated");
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
            assertEq(adapter.netCredit(marketId), 1e18, "cap accounting not updated");
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
        emit IMidnightAdapter.UpdateMarket(marketId, 0, 0);
        vm.prank(signerAllocator);
        adapter.withdrawToVault(offer.market, 0);

        assertEq(adapter.marketIdsLength(), 0, "market removed");
        assertEq(adapter.netCredit(marketId), 0, "netCredit");
        assertEq(adapter.maturities(offer.market.maturity).netCredit, 0, "maturity netCredit");
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
        uint128 netCredit = adapter.netCredit(marketId);
        assertEq(netCredit, offer.maxUnits - pendingFee, "net credit excludes the pending fee");

        // The fee accrues out of the credit and of the pending fee alike, so the net credit does not move.
        skip(duration / 2);
        uint256 valueBefore = adapter.realAssets();
        new MidnightLossRealizer(address(midnight)).realizeLoss(adapter, offer.market);
        assertLt(midnight.pendingFee(marketId, address(adapter)), pendingFee, "fee accrued");
        uint128 netCreditAfter = adapter.netCredit(marketId);
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
        vm.expectRevert(IMidnightAdapter.BuyAtLoss.selector);
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

        vm.expectRevert(IMidnightAdapter.BuyPostMaturity.selector);
        take(offer);
    }

    function testForceDeallocateWithSettlementFee(uint256 assets, uint256 feeCbp) public {
        assets = bound(assets, 1, 1e18);
        feeCbp = bound(feeCbp, 0, MAX_SETTLEMENT_FEE_0_DAYS / CBP);
        for (uint256 i = 0; i <= 6; i++) {
            midnight.setDefaultSettlementFee(address(loanToken), i, feeCbp * CBP);
        }
        Offer memory offer = buy(7 days, 1e18);
        skip(1);
        uint256 vaultBalanceBefore = loanToken.balanceOf(address(parentVault));
        uint256 claimableFeeBefore = midnight.claimableSettlementFee(address(loanToken));
        uint256 settlementFee = assets.mulDivUp(feeCbp * CBP, 1e18);
        deal(address(loanToken), address(this), settlementFee);
        loanToken.approve(address(adapter), settlementFee);

        forceDeallocate(offer.market, assets);

        assertEq(loanToken.balanceOf(address(parentVault)), vaultBalanceBefore + assets, "vault balance");
        uint128 netCredit = adapter.netCredit(_marketId(offer.market));
        assertEq(netCredit, 1e18 - assets, "netCredit");
        assertEq(loanToken.balanceOf(address(this)), 0, "caller paid settlement fee");
        assertEq(loanToken.allowance(address(this), address(adapter)), 0, "exact fee allowance consumed");
        assertEq(loanToken.balanceOf(address(adapter)), 0, "adapter balance");
        assertEq(
            midnight.claimableSettlementFee(address(loanToken)), claimableFeeBefore + settlementFee, "settlement fee"
        );
    }

    function testForceDeallocateWithSettlementFeeReverts(bool funded) public {
        for (uint256 i = 0; i <= 6; i++) {
            midnight.setDefaultSettlementFee(address(loanToken), i, 10 * CBP);
        }
        Offer memory boughtOffer = buy(7 days, 1e18);
        (Offer memory offer, bytes32 root_) = makeForceDeallocateOffer(boughtOffer.market, 0.5e18);
        uint256 vaultBalanceBefore = loanToken.balanceOf(address(parentVault));
        if (funded) deal(address(loanToken), address(this), 0.5e18);
        else loanToken.approve(address(adapter), type(uint256).max);

        vm.expectRevert(ErrorsLib.TransferFromReverted.selector);
        parentVault.forceDeallocate(
            address(adapter), abi.encode(offer, abi.encode(root_, 0, proof([offer]))), 0.5e18, address(this)
        );

        assertEq(adapter.netCredit(_marketId(offer.market)), 1e18, "netCredit unchanged");
        assertEq(midnight.credit(_marketId(offer.market), address(adapter)), 1e18, "sale reverted");
        assertEq(loanToken.balanceOf(address(parentVault)), vaultBalanceBefore, "vault balance unchanged");
    }

    /// forge-config: default.isolate = true
    function testForceDeallocateRealVaultWithSettlementFee() public {
        setUpRealVault();
        for (uint256 i = 0; i <= 6; i++) {
            midnight.setDefaultSettlementFee(address(loanToken), i, 10 * CBP);
        }
        Offer memory boughtOffer = buyOnRealVault(7 days, 1e18);
        skip(1);
        (Offer memory offer, bytes32 root_) = makeForceDeallocateOffer(boughtOffer.market, 0.5e18);
        uint256 settlementFee = uint256(0.5e18).mulDivUp(10 * CBP, 1e18);
        uint256 sharesBefore = realVault.balanceOf(address(this));
        uint256 expectedPenaltyShares = realVault.previewWithdraw(0.01e18);
        realVault.approve(taker, expectedPenaltyShares);
        deal(address(loanToken), taker, settlementFee);
        vm.startPrank(taker);
        loanToken.approve(address(adapter), settlementFee);

        uint256 penaltyShares = realVault.forceDeallocate(
            address(adapter), abi.encode(offer, abi.encode(root_, 0, proof([offer]))), 0.5e18, address(this)
        );
        vm.stopPrank();

        assertEq(penaltyShares, expectedPenaltyShares, "penalty shares");
        assertEq(realVault.balanceOf(address(this)), sharesBefore - penaltyShares, "penalty charged to onBehalf");
        assertEq(loanToken.balanceOf(taker), 0, "settlement fee charged to caller");
        assertEq(loanToken.balanceOf(address(this)), 0, "onBehalf token balance");
        assertEq(loanToken.balanceOf(address(adapter)), 0, "adapter balance");
        assertEq(loanToken.balanceOf(address(realVault)), 9.5e18, "vault balance");
        assertEq(adapter.netCredit(_marketId(offer.market)), 0.5e18, "netCredit");
        assertEq(realVault.allocation(adapter.adapterId()), 0.5e18, "allocation");
        assertEq(realVault.totalAssets(), 10e18 - 0.01e18, "only penalty reduces totalAssets");
    }

    /* CALLBACKS */

    function testOnBuyNotMidnight(address caller) public {
        vm.assume(caller != address(midnight));
        vm.prank(caller);
        vm.expectRevert(IMidnightAdapter.NotMidnight.selector);
        adapter.onBuy(bytes32(0), storedOffer.market, 0, 0, 0, address(adapter), "");
    }

    function testOnBuyNotSelf(address buyer) public {
        vm.assume(buyer != address(adapter));
        vm.prank(address(midnight));
        vm.expectRevert(IMidnightAdapter.NotSelf.selector);
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

        uint128 netCredit = adapter.netCredit(_marketId(offer.market));
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
        vm.expectRevert(IMidnightAdapter.NotMidnight.selector);
        adapter.onSell(bytes32(0), storedOffer.market, 0, 0, 0, address(adapter), address(adapter), "");
    }

    function testOnSellNotSelf(address seller) public {
        vm.assume(seller != address(adapter));
        vm.prank(address(midnight));
        vm.expectRevert(IMidnightAdapter.NotSelf.selector);
        adapter.onSell(bytes32(0), storedOffer.market, 0, 0, 0, seller, address(adapter), "");
    }

    function testDeallocateNotParentVault(address caller) public {
        vm.assume(caller != address(parentVault));
        vm.prank(caller);
        vm.expectRevert(IMidnightAdapter.NotAuthorized.selector);
        adapter.deallocate("", 0, bytes4(0), caller);
    }

    /// @dev Only the adapter can allocate and deallocate through the vault, so it cannot be a liquidity adapter.
    function testVaultAllocateAndDeallocateRevert() public {
        vm.expectRevert(IMidnightAdapter.SelfAllocationOnly.selector);
        parentVault.allocate(address(adapter), "", 0);
        vm.expectRevert(IMidnightAdapter.SelfAllocationOnly.selector);
        parentVault.deallocate(address(adapter), "", 0);
    }

    /* SET CONSUMED */

    function testSetConsumedNotAuthorized(address caller) public {
        vm.assume(!parentVault.isAllocator(caller) && !parentVault.isSentinel(caller));
        vm.prank(caller);
        vm.expectRevert(IMidnightAdapter.NotAuthorized.selector);
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
        emit IMidnightAdapter.SetConsumed(caller, offer.group, type(uint128).max);
        vm.prank(caller);
        adapter.setConsumed(offer.group, type(uint128).max);
        assertEq(midnight.consumed(address(adapter), offer.group), type(uint128).max, "consumed");

        bytes memory data = sign([offer], signerAllocator);
        vm.expectRevert(IMidnight.ConsumedUnits.selector);
        this.takeWithAccrual(offer, data, taker, address(0));
    }

    /* TAKE */

    function testTakeLoanAssetMismatch() public {
        Offer memory offer = storedOffer;
        offer.market.loanToken = address(rewardToken);
        vm.prank(signerAllocator);
        vm.expectRevert(IMidnightAdapter.LoanAssetMismatch.selector);
        adapter.take(offer, "", 0);
    }

    /// @dev Selling more than its credit would put the adapter in debt, which it has no collateral for.
    function testTakeMoreThanPositionReverts() public {
        Offer memory offer = buy(7 days, 1e18);
        Offer memory buyOffer = makeExternalOffer(offer.market, true, 2e18, MAX_TICK);

        vm.expectRevert(IMidnight.SellerIsLiquidatable.selector);
        vm.prank(signerAllocator);
        adapter.take(buyOffer, "", 2e18);
    }

    /* FORCE DEALLOCATE */

    function testForceDeallocateMoreThanPositionReverts() public {
        Offer memory boughtOffer = buy(7 days, 1e18);
        (Offer memory offer, bytes32 root_) = makeForceDeallocateOffer(boughtOffer.market, 2e18);

        vm.expectRevert(IMidnight.SellerIsLiquidatable.selector);
        parentVault.forceDeallocate(
            address(adapter), abi.encode(offer, abi.encode(root_, 0, proof([offer]))), 2e18, address(this)
        );
    }

    function testForceDeallocateOK() public {
        Offer memory boughtOffer = buy(7 days, 1e18);
        bytes32 marketId = _marketId(boughtOffer.market);

        (Offer memory offer, bytes32 root_) = makeForceDeallocateOffer(boughtOffer.market, 0.5e18);
        vm.expectEmit(address(adapter));
        emit IMidnightAdapter.ForceDeallocate(marketId, 0.5e18, 0.5e18);
        parentVault.forceDeallocate(
            address(adapter), abi.encode(offer, abi.encode(root_, 0, proof([offer]))), 0.5e18, address(this)
        );

        uint128 marketNetCredit = adapter.netCredit(marketId);
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

    function testForceDeallocateWithoutRole() public {
        Offer memory boughtOffer = buy(7 days, 1e18);
        skip(1);

        // Simulate the adapter having no role: any vault.deallocate call from the adapter reverts.
        vm.mockCallRevert(address(parentVault), abi.encodeWithSelector(VaultV2Mock.deallocate.selector), "no role");

        forceDeallocate(boughtOffer.market, 0.5e18);

        assertEq(parentVault.allocation(durationId(1 days)), 0.5e18, "1 day");
        assertEq(parentVault.allocation(durationId(7 days)), 0.5e18, "7 days, stale");
        uint128 marketNetCredit = adapter.netCredit(_marketId(boughtOffer.market));
        assertEq(marketNetCredit, 0.5e18, "netCredit");

        vm.expectRevert(bytes("no role"));
        adapter.updateDurationCaps(boughtOffer.market.maturity);
    }

    /// forge-config: default.isolate = true
    /// @dev Runs on a real VaultV2, with a non-zero penalty, fees and maxRate, and with the adapter's allocator role
    /// revoked before the exit.
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
        uint128 marketNetCredit = adapter.netCredit(_marketId(offer.market));
        assertEq(marketNetCredit, 0.5e18, "netCredit");
        assertEq(realVault.allocation(durationId(7 days)), 0.5e18, "7 days stale");
        assertEq(realVault.allocation(durationId(1 days)), 0.5e18, "1 day");
        assertEq(loanToken.balanceOf(address(realVault)), 9.5e18, "vault balance");
    }

    /// forge-config: default.isolate = true
    /// @dev A sendSharesGate blocking the adapter affects neither exits nor duration caps updates.
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
        assertEq(realVault.allocation(durationId(7 days)), 0.5e18, "7 days stale");

        adapter.updateDurationCaps(offer.market.maturity);
        assertEq(realVault.allocation(durationId(7 days)), 0, "7 days zeroed");
        assertEq(realVault.allocation(durationId(1 days)), 0.5e18, "1 day");
    }

    /// forge-config: default.isolate = true
    /// @dev A matured maturity zeroes all its duration ids at once, without touching Midnight. The adapter needs the
    /// allocator or sentinel role.
    function testUpdateDurationCapsMaturedRealVault() public {
        setUpRealVault();
        Offer memory offer = buyOnRealVault(7 days, 1e18);
        submitAndCall(realVault, abi.encodeCall(IVaultV2.setIsAllocator, (address(adapter), false)));

        skip(7 days + 1);

        vm.expectRevert(ErrorsLib.Unauthorized.selector);
        adapter.updateDurationCaps(offer.market.maturity);

        vm.prank(owner);
        realVault.setIsSentinel(address(adapter), true);
        vm.expectEmit(address(adapter));
        emit IMidnightAdapter.UpdateDurationCaps(offer.market.maturity, 0, 1e18);
        adapter.updateDurationCaps(offer.market.maturity);

        assertEq(realVault.allocation(durationId(1 days)), 0, "1 day zeroed");
        assertEq(realVault.allocation(durationId(7 days)), 0, "7 days zeroed");
        assertEq(realVault.allocation(adapter.adapterId()), 1e18, "adapter id untouched");
    }

    /// forge-config: default.isolate = true
    /// @dev Zeroing a maturity's stale duration id must not touch other maturities sharing that id.
    function testForceDeallocateRealVaultSharedDurationId() public {
        setUpRealVault();
        Offer memory offerA = buyOnRealVault(7 days, 1e18);
        buyOnRealVault(10 days, 1e18);

        skip(1);

        forceDeallocateOnRealVault(offerA.market, 0.5e18);
        assertEq(realVault.allocation(durationId(7 days)), 1.5e18, "7 days stale");

        adapter.updateDurationCaps(offerA.market.maturity);

        assertEq(realVault.allocation(durationId(7 days)), 1e18, "7 days keeps the other maturity's part");
        assertEq(realVault.allocation(durationId(1 days)), 1.5e18, "1 day");
        assertEq(realVault.allocation(adapter.adapterId()), 1.5e18, "adapter id");
    }

    /// forge-config: default.isolate = true
    /// @dev An allocator takes external offers directly: taking a sell offer buys credit, taking a buy offer
    /// sells it. Both route through the same onBuy/onSell accounting as the maker flows.
    function testAllocatorTakeRealVault() public {
        setUpRealVault();
        Market memory market = makeBuyOffer(7 days, 1e18, MAX_TICK).market;
        bytes32 marketId = _marketId(market);

        Offer memory sellOffer = makeExternalOffer(market, false, 1e18, MAX_TICK);
        vm.expectRevert(IMidnightAdapter.NotAuthorized.selector);
        adapter.take(sellOffer, "", uint256(sellOffer.maxUnits));

        // Buy 1e18 credit by taking the external sell offer, funded by the vault.
        vm.prank(signerAllocator);
        adapter.take(sellOffer, "", uint256(sellOffer.maxUnits));

        assertEq(realVault.allocation(adapter.adapterId()), 1e18, "allocation after buy");
        assertEq(realVault.allocation(durationId(7 days)), 1e18, "duration allocation after buy");
        assertEq(loanToken.balanceOf(address(realVault)), 9e18, "vault funded the buy");
        assertEq(adapter.realAssets(), 1e18, "adapter realAssets after buy");

        skip(1);

        // Sell 0.5e18 credit by taking an external buy offer, proceeds forwarded to the vault.
        Offer memory buyOffer = makeExternalOffer(market, true, 0.5e18, MAX_TICK);
        vm.prank(signerAllocator);
        adapter.take(buyOffer, "", uint256(buyOffer.maxUnits));

        uint128 marketNetCredit = adapter.netCredit(marketId);
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
        bytes memory data = sign([offer], signerAllocator);
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

        this.takeWithAccrual(offer, sign([offer], signerAllocator), taker, address(this));

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
        vm.expectRevert(IMidnightAdapter.OtherSellInProgress.selector);
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
        assertEq(adapter.netCredit(marketId), 1e18, "cap accounting not updated");
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
    /// @dev A market whose oracle permanently reverts can be abandoned from maturity + 3 days.
    function testCanAbandonMarketWithRevertingOracleThreeDaysAfterMaturity() public {
        setUpRealVault();
        Offer memory boughtOffer = buyOnRealVault(7 days, 1e18);
        bytes32 marketId = _marketId(boughtOffer.market);

        skip(7 days + 1);
        vm.mockCallRevert(storedCollaterals[0].oracle, abi.encodeWithSignature("price()"), bytes("dead oracle"));

        vm.expectRevert(bytes("dead oracle"));
        midnight.liquidate(boughtOffer.market, 0, 0, 0, taker, true, address(this), address(0), "");
        assertEq(midnight.lossFactor(marketId), 0, "loss not realized");
        assertEq(realVault.totalAssets(), 10e18, "market still fully valued");

        assertEq(
            adapter.maxSellRate(keccak256(abi.encode(boughtOffer.market.collateralParams))), 0, "default maximum rate"
        );
        setMaxSellRate(boughtOffer.market, 1);

        address buyer = makeAddr("buyer");
        Offer memory sellOffer = makeSellOffer(boughtOffer.market, 1e18, 0);
        vm.expectRevert(stdError.arithmeticError);
        this.takeWithAccrual(sellOffer, sign([sellOffer], signerAllocator), buyer, address(0));

        assertEq(midnight.credit(marketId, address(adapter)), 1e18, "adapter credit");
        assertEq(midnight.credit(marketId, buyer), 0, "buyer credit");
        assertEq(midnight.debt(marketId, taker), 1e18, "borrower debt");
        assertEq(adapter.realAssets(), 1e18, "adapter realAssets");
        assertEq(realVault.totalAssets(), 10e18, "sale reverted");

        bytes32[] memory marketIds = adapter.ids(boughtOffer.market);
        for (uint256 i = 0; i < marketIds.length; i++) {
            assertEq(realVault.allocation(marketIds[i]), 1e18, "allocation");
        }

        skip(adapter.NO_SELL_CHECK_DELAY() - 2);
        sellOffer.expiry = block.timestamp;
        vm.expectRevert(stdError.arithmeticError);
        this.takeWithAccrual(sellOffer, sign([sellOffer], signerAllocator), buyer, address(0));

        skip(1);
        sellOffer.expiry = block.timestamp;
        this.takeWithAccrual(sellOffer, sign([sellOffer], signerAllocator), buyer, address(0));

        assertEq(midnight.credit(marketId, address(adapter)), 0, "adapter credit cleared");
        assertEq(midnight.credit(marketId, buyer), 1e18, "buyer received position");
        assertEq(adapter.marketIdsLength(), 0, "market removed");
        assertEq(adapter.realAssets(), 0, "adapter realAssets");
        assertEq(realVault.totalAssets(), 9e18, "loss realized");
        for (uint256 i = 0; i < marketIds.length; i++) {
            assertEq(realVault.allocation(marketIds[i]), 0, "allocation cleared");
        }
    }

    /* STALE DURATION IDS */

    /// forge-config: default.isolate = true
    /// @dev Duration ids go stale as time passes, a full sell still removes the maturity from all of them.
    function testStaleDurationIdsSyncedOnFullSell(uint256 elapsed) public {
        elapsed = bound(elapsed, 1, 7 days - 1);
        setUpRealVault();
        Offer memory offer = buyOnRealVault(7 days, 1e18);

        skip(elapsed);
        assertEq(realVault.allocation(durationId(7 days)), 1e18, "7 days stale before sell");

        sellUnits(offer.market, 1e18, MAX_TICK);

        assertEq(realVault.allocation(durationId(1 days)), 0, "1 day");
        assertEq(realVault.allocation(durationId(7 days)), 0, "7 days");
        assertEq(realVault.allocation(adapter.adapterId()), 0, "adapter id");
    }

    /// forge-config: default.isolate = true
    function testStaleDurationIdsSyncedOnFullWithdraw() public {
        setUpRealVault();
        Offer memory offer = buyOnRealVault(7 days, 1e18);

        skip(7 days);
        vm.prank(taker);
        midnight.repay(offer.market, 1e18, taker, address(0), "");
        assertEq(realVault.allocation(durationId(1 days)), 1e18, "1 day stale before withdraw");
        assertEq(realVault.allocation(durationId(7 days)), 1e18, "7 days stale before withdraw");

        vm.prank(signerAllocator);
        adapter.withdrawToVault(offer.market, 1e18);

        assertEq(realVault.allocation(durationId(1 days)), 0, "1 day");
        assertEq(realVault.allocation(durationId(7 days)), 0, "7 days");
        assertEq(realVault.allocation(adapter.adapterId()), 0, "adapter id");
    }

    /// forge-config: default.isolate = true
    function testStaleDurationIdsSyncedOnFullForceDeallocate() public {
        setUpRealVault();
        Offer memory offer = buyOnRealVault(7 days, 1e18);

        skip(6 days + 1);
        assertEq(realVault.allocation(durationId(1 days)), 1e18, "1 day stale before exit");
        assertEq(realVault.allocation(durationId(7 days)), 1e18, "7 days stale before exit");

        forceDeallocateOnRealVault(offer.market, 1e18);

        assertEq(realVault.allocation(durationId(1 days)), 0, "1 day");
        assertEq(realVault.allocation(durationId(7 days)), 0, "7 days");
        assertEq(realVault.allocation(adapter.adapterId()), 0, "adapter id");
    }

    /// forge-config: default.isolate = true
    /// @dev Partial exits decrease stale ids too, so they stay consistent with the stored duration count.
    function testStaleDurationIdsPartialSellThenUpdateThenFullSell() public {
        setUpRealVault();
        Offer memory offer = buyOnRealVault(7 days, 1e18);

        skip(1 days);
        sellUnits(offer.market, 0.25e18, MAX_TICK);
        assertEq(realVault.allocation(durationId(1 days)), 0.75e18, "1 day after partial sell");
        assertEq(realVault.allocation(durationId(7 days)), 0.75e18, "7 days stale after partial sell");

        adapter.updateDurationCaps(offer.market.maturity);
        assertEq(realVault.allocation(durationId(1 days)), 0.75e18, "1 day after update");
        assertEq(realVault.allocation(durationId(7 days)), 0, "7 days after update");

        sellUnits(offer.market, 0.25e18, MAX_TICK);
        assertEq(realVault.allocation(durationId(1 days)), 0.5e18, "1 day after second partial sell");
        assertEq(realVault.allocation(durationId(7 days)), 0, "7 days after second partial sell");

        skip(5 days + 1);
        sellUnits(offer.market, 0.5e18, MAX_TICK);
        assertEq(realVault.allocation(durationId(1 days)), 0, "1 day");
        assertEq(realVault.allocation(durationId(7 days)), 0, "7 days");
        assertEq(realVault.allocation(adapter.adapterId()), 0, "adapter id");
    }

    /// forge-config: default.isolate = true
    /// @dev A buy on a maturity with stale ids is counted on them too, so that a full exit zeroes them.
    function testStaleDurationIdsSecondBuyThenFullSell() public {
        setUpRealVault();
        Offer memory offer = buyOnRealVault(7 days, 1e18);

        skip(1 days);
        buyOnRealVault(6 days, 1e18);
        assertEq(realVault.allocation(durationId(1 days)), 2e18, "1 day counts both buys");
        assertEq(realVault.allocation(durationId(7 days)), 2e18, "7 days stale counts both buys");

        sellUnits(offer.market, 2e18, MAX_TICK);

        assertEq(realVault.allocation(durationId(1 days)), 0, "1 day");
        assertEq(realVault.allocation(durationId(7 days)), 0, "7 days");
        assertEq(realVault.allocation(adapter.adapterId()), 0, "adapter id");
    }

    /// forge-config: default.isolate = true
    /// @dev Once a maturity is emptied, its next buy is only counted on the durations it currently fills.
    function testDurationIdsResetOnRebuyAfterFullSell() public {
        setUpRealVault();
        Offer memory offer = buyOnRealVault(7 days, 1e18);

        skip(1 days);
        sellUnits(offer.market, 1e18, MAX_TICK);
        assertEq(realVault.allocation(durationId(7 days)), 0, "7 days after full sell");

        adapter.updateDurationCaps(offer.market.maturity);
        buyOnRealVault(6 days, 1e18);
        assertEq(realVault.allocation(durationId(1 days)), 1e18, "1 day after rebuy");
        assertEq(realVault.allocation(durationId(7 days)), 0, "7 days after rebuy");
    }

    /// forge-config: default.isolate = true
    /// @dev A full sell only removes its own maturity from the shared duration ids.
    function testStaleDurationIdsFullSellKeepsOtherMaturity() public {
        setUpRealVault();
        bytes memory idData = abi.encode("duration", uint256(30 days));
        submitAndCall(realVault, abi.encodeCall(IVaultV2.increaseAbsoluteCap, (idData, type(uint128).max)));
        submitAndCall(realVault, abi.encodeCall(IVaultV2.increaseRelativeCap, (idData, 1e18)));
        Offer memory offerA = buyOnRealVault(7 days, 1e18);
        Offer memory offerB = buyOnRealVault(30 days, 2e18);

        skip(6 days + 1);
        sellUnits(offerA.market, 1e18, MAX_TICK);

        assertEq(realVault.allocation(durationId(1 days)), 2e18, "1 day");
        assertEq(realVault.allocation(durationId(7 days)), 2e18, "7 days");
        assertEq(realVault.allocation(durationId(30 days)), 2e18, "30 days stale for the other maturity");
        assertEq(realVault.allocation(adapter.adapterId()), 2e18, "adapter id");

        adapter.updateDurationCaps(offerB.market.maturity);
        assertEq(realVault.allocation(durationId(7 days)), 2e18, "7 days after update");
        assertEq(realVault.allocation(durationId(30 days)), 0, "30 days after update");
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
        uint128 creditBefore = adapter.netCredit(marketId);
        uint256 vaultBalanceBefore = loanToken.balanceOf(address(parentVault));

        skip(7 days);

        deal(address(loanToken), address(this), 1e18);
        loanToken.approve(address(midnight), type(uint256).max);
        midnight.repay(boughtOffer.market, 1e18, taker, address(0), "");

        uint256 withdrawAmount = 0.5e18;
        vm.expectEmit(address(adapter));
        emit IMidnightAdapter.WithdrawToVault(marketId, withdrawAmount, withdrawAmount);
        vm.prank(caller);
        adapter.withdrawToVault(boughtOffer.market, withdrawAmount);

        uint128 creditAfter = adapter.netCredit(marketId);
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
        uint128 netCredit = adapter.netCredit(marketId);
        assertApproxEqAbs(netCredit, 0.2e18, 1, "netCredit");
        assertApproxEqAbs(adapter.realAssets(), 0.2e18, 1, "realAssets");
        assertApproxEqAbs(parentVault.allocation(adapter.adapterId()), 0.2e18, 1, "allocation");
    }

    /* SKIM */

    function testSetSkimRecipientNotAuthorized(address caller) public {
        vm.assume(caller != curator);
        vm.expectRevert(IMidnightAdapter.NotAuthorized.selector);
        vm.prank(caller);
        adapter.submit(abi.encodeCall(IMidnightAdapter.setSkimRecipient, (recipient)));
    }

    function testSetSkimRecipientNotTimelocked() public {
        vm.expectRevert(IMidnightAdapter.DataNotTimelocked.selector);
        adapter.setSkimRecipient(recipient);
    }

    function testSetSkimRecipientTimelockNotExpired(uint256 timelockDuration) public {
        timelockDuration = bound(timelockDuration, 1, 3650 days);
        submitTimelock(IMidnightAdapter.setSkimRecipient.selector, timelockDuration);

        vm.prank(curator);
        adapter.submit(abi.encodeCall(IMidnightAdapter.setSkimRecipient, (recipient)));

        vm.expectRevert(IMidnightAdapter.TimelockNotExpired.selector);
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
        vm.expectRevert(IMidnightAdapter.NotAuthorized.selector);
        adapter.skim(address(rewardToken));
    }

    function testSkimOK() public {
        setSkimRecipient(recipient);

        uint256 balance = 123e18;
        deal(address(rewardToken), address(adapter), balance);

        vm.expectEmit(true, false, false, true, address(adapter));
        emit IMidnightAdapter.Skim(address(rewardToken), balance);
        vm.prank(recipient);
        adapter.skim(address(rewardToken));

        assertEq(rewardToken.balanceOf(recipient), balance, "recipient received");
        assertEq(rewardToken.balanceOf(address(adapter)), 0, "adapter drained");
    }

    /* NET CREDIT BOUNDS */

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
        uint256 netCreditLoss = uint256(type(uint128).max) - currentCredit;
        uint256 expectedNetCredit = currentCredit + boughtNetCredit;
        assertGt(uint256(adapter.netCredit(marketId)) + boughtNetCredit, type(uint128).max, "wide sum");
        assertLe(expectedNetCredit, type(uint128).max, "final credit fits");

        deal(address(loanToken), address(parentVault), boughtNetCredit);
        offer.maxUnits = uint128(boughtNetCredit);
        offer.group = bytes32("second buy");
        vm.expectEmit(address(adapter));
        emit IMidnightAdapter.Buy(marketId, boughtNetCredit, boughtNetCredit, netCreditLoss);
        take(offer);

        assertEq(adapter.netCredit(marketId), expectedNetCredit, "market netCredit");
        assertEq(adapter.maturities(offer.market.maturity).netCredit, expectedNetCredit, "maturity netCredit");
        assertEq(adapter.realAssets(), expectedNetCredit, "realAssets");
        assertEq(parentVault.allocation(adapter.adapterId()), expectedNetCredit, "allocation");
    }

    function testOnSellMaxNetCredit() public {
        Offer memory offer = buyMaxNetCredit();
        bytes32 marketId = _marketId(offer.market);
        uint256 assets = uint256(type(uint128).max) - 1;

        vm.expectEmit(address(adapter));
        emit IMidnightAdapter.Sell(marketId, assets, assets);
        sell(offer.market, assets);

        assertEq(adapter.netCredit(marketId), 1, "market netCredit");
        assertEq(adapter.maturities(offer.market.maturity).netCredit, 1, "maturity netCredit");
        assertEq(adapter.realAssets(), 1, "realAssets");
        assertEq(parentVault.allocation(adapter.adapterId()), 1, "allocation");
        assertEq(loanToken.balanceOf(address(parentVault)), assets, "vault balance");
    }

    function testForceDeallocateMaxNetCredit() public {
        Offer memory boughtOffer = buyMaxNetCredit();
        bytes32 marketId = _marketId(boughtOffer.market);
        uint256 assets = uint256(type(uint128).max) - 1;
        (Offer memory offer, bytes32 root_) = makeForceDeallocateOffer(boughtOffer.market, assets);

        vm.expectEmit(address(adapter));
        emit IMidnightAdapter.ForceDeallocate(marketId, assets, assets);
        (, int256 change) = parentVault.forceDeallocate(
            address(adapter), abi.encode(offer, abi.encode(root_, 0, proof([offer]))), assets, address(this)
        );

        assertEq(change, -int256(assets), "change");
        assertEq(adapter.netCredit(marketId), 1, "market netCredit");
        assertEq(adapter.maturities(offer.market.maturity).netCredit, 1, "maturity netCredit");
        assertEq(adapter.realAssets(), 1, "realAssets");
        assertEq(parentVault.allocation(adapter.adapterId()), 1, "allocation");
        assertEq(loanToken.balanceOf(address(parentVault)), assets, "vault balance");
    }

    function testWithdrawToVaultMaxNetCredit() public {
        Offer memory offer = buyMaxNetCredit();
        bytes32 marketId = _marketId(offer.market);
        uint256 assets = uint256(type(uint128).max) - 1;
        skip(7 days);

        vm.prank(taker);
        midnight.repay(offer.market, type(uint128).max, taker, address(0), "");
        vm.expectEmit(address(adapter));
        emit IMidnightAdapter.WithdrawToVault(marketId, assets, assets);
        vm.prank(signerAllocator);
        adapter.withdrawToVault(offer.market, assets);

        assertEq(adapter.netCredit(marketId), 1, "market netCredit");
        assertEq(adapter.maturities(offer.market.maturity).netCredit, 1, "maturity netCredit");
        assertEq(adapter.realAssets(), 1, "realAssets");
        assertEq(parentVault.allocation(adapter.adapterId()), 1, "allocation");
        assertEq(loanToken.balanceOf(address(parentVault)), assets, "vault balance");
    }

    /* HELPERS */

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
        adapter.submit(abi.encodeCall(IMidnightAdapter.setSkimRecipient, (newSkimRecipient)));
        vm.expectEmit(true, false, false, false, address(adapter));
        emit IMidnightAdapter.SetSkimRecipient(newSkimRecipient);
        adapter.setSkimRecipient(newSkimRecipient);
    }

    function submitTimelock(bytes4 selector, uint256 duration) internal {
        vm.prank(curator);
        adapter.submit(abi.encodeCall(IMidnightAdapter.increaseTimelock, (selector, duration)));
        adapter.increaseTimelock(selector, duration);
    }

    function addSubRatifier(IMidnightAdapter _adapter, address subRatifier) internal {
        vm.prank(curator);
        _adapter.submit(abi.encodeCall(IMidnightAdapter.addSubRatifier, (subRatifier)));
        _adapter.addSubRatifier(subRatifier);
    }

    function setMaxSellRate(Market memory market, uint256 newMaxSellRate) internal {
        bytes32 collateralParamsHash = keccak256(abi.encode(market.collateralParams));
        vm.prank(curator);
        adapter.setMaxSellRate(collateralParamsHash, newMaxSellRate);
    }

    function setMinRate(uint256 newMinRate) internal {
        vm.prank(curator);
        adapter.setMinRate(newMinRate);
    }

    function take(Offer memory offer) internal {
        this.takeWithAccrual(offer, sign([offer], signerAllocator), taker, address(0));
    }

    /// @dev Keeps accrual and take in one transaction when tests run with isolation.
    function takeWithAccrual(Offer memory offer, bytes memory data, address account, address callback) external {
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
        this.takeWithAccrual(offer, sign([offer], signerAllocator), taker, address(0));
    }

    function sellUnits(Market memory market, uint256 units, uint256 tick) internal {
        Offer memory offer = makeSellOffer(market, units, tick);
        this.takeWithAccrual(offer, sign([offer], signerAllocator), taker, address(0));
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
        offer.maxUnits = uint128(assets);
        offer.expiry = block.timestamp;
        offer.callback = address(0);
        offer.callbackData = hex"";
        offer.ratifier = address(approvalRatifier);
        offer.group = bytes32(vm.randomUint());

        deal(address(loanToken), buyer, offer.maxUnits);
        vm.startPrank(buyer);
        loanToken.approve(address(midnight), type(uint256).max);
        midnight.setIsAuthorized(address(approvalRatifier), true, buyer);
        root_ = root([offer]);
        approvalRatifier.setIsRootRatified(buyer, root_, true);
        vm.stopPrank();
    }

    /// @dev Builds an external offer at `tick`, ratified by this contract. Buy offers get a funded maker, sell
    /// offers get a collateralized one.
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
        (Offer memory offer, bytes32 root_) = makeForceDeallocateOffer(market, assets);
        bytes memory data = abi.encode(offer, abi.encode(root_, 0, proof([offer])));
        parentVault.forceDeallocate(address(adapter), data, assets, address(this));
    }

    function setUpRealVault() internal {
        realVault = IVaultV2(deployCode("VaultV2.sol:VaultV2", abi.encode(owner, address(loanToken))));
        vm.prank(owner);
        realVault.setCurator(curator);
        adapter = IMidnightAdapter(factory.createMidnightAdapter(address(realVault), address(midnight)));

        submitAndCall(realVault, abi.encodeCall(IVaultV2.addAdapter, (address(adapter))));
        submitAndCall(realVault, abi.encodeCall(IVaultV2.setIsAllocator, (address(adapter), true)));
        submitAndCall(realVault, abi.encodeCall(IVaultV2.setIsAllocator, (signerAllocator, true)));
        addSubRatifier(adapter, address(ecrecoverRatifier));
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
        idDatas[5] = abi.encode("duration", uint256(1 days));
        idDatas[6] = abi.encode("duration", uint256(7 days));
        idDatas[7] = abi.encode("marketConfig", address(0), address(0), uint256(0));
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
        (Offer memory offer, bytes32 root_) = makeForceDeallocateOffer(market, assets);
        bytes memory data = abi.encode(offer, abi.encode(root_, 0, proof([offer])));
        return realVault.forceDeallocate(address(adapter), data, assets, address(this));
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

    function durationId(uint256 duration) internal pure returns (bytes32) {
        return keccak256(abi.encode("duration", duration));
    }

    function setMidnightCredit(bytes32 marketId, address account, uint256 credit) internal {
        stdstore.target(address(midnight))
            .sig("credit(bytes32,address)")
            .with_key(marketId)
            .with_key(account)
            .checked_write(credit);
    }

    function assertCurrentNetCredit(Market memory market, uint256 growth) internal view {
        bytes32 marketId = _marketId(market);
        (uint128 credit, uint128 pendingFee,) = midnight.updatePositionView(market, marketId, address(adapter));
        uint256 netCredit = credit - pendingFee;
        uint256 timeToMaturity = market.maturity.zeroFloorSub(block.timestamp);
        assertEq(
            adapter.realAssets(),
            netCredit - netCredit.mulDivUp(growth * timeToMaturity, 1e18),
            "real maturity still determines growth"
        );
    }

    function assertMarketIndex(bytes32 marketId, uint256 expected) internal {
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
        return abi.encode(address(ecrecoverRatifier), innerRatifierData(_root, signer, leafIndex, _proof));
    }

    function innerRatifierData(bytes32 _root, address signer, uint256 leafIndex, bytes32[] memory _proof)
        internal
        view
        returns (bytes memory)
    {
        bytes32 structHash = keccak256(abi.encode(HashLib.offerTreeTypeHash(_proof.length), _root));
        bytes32 domainSeparator =
            keccak256(abi.encode(EIP712_DOMAIN_TYPEHASH, block.chainid, address(ecrecoverRatifier)));
        bytes32 digest = keccak256(bytes.concat("\x19\x01", domainSeparator, structHash));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(privateKey[signer], digest);
        return abi.encode(Signature({v: v, r: r, s: s}), _root, leafIndex, _proof);
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
        bytes memory data = sign([offer], signerAllocator);
        vm.prank(taker);
        midnight.take(offer, data, offer.maxUnits, taker, offer.buy ? taker : address(0), address(0), "");
    }

    function newCallback() internal returns (EagerLossCallback callback) {
        callback = new EagerLossCallback(address(midnight), address(loanToken), address(realVault));
        deal(address(loanToken), address(callback), 100e18);
    }

    function callbackSale(Offer memory offer, EagerLossCallback callback) internal {
        midnight.take(
            offer, sign([offer], signerAllocator), offer.maxUnits, address(callback), address(0), address(callback), ""
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
        vm.expectRevert(IMidnightAdapter.SellRateTooHigh.selector);
        directTake(offer);
    }

    /// forge-config: default.isolate = true
    function testEagerLossUncoveredSaleAfterDefaultReverts() public {
        Offer memory initial = freshPosition(MAX_TICK);
        setMaxSellRate(initial.market, 1);
        this.realizeDefault(initial.market, ORACLE_PRICE_SCALE / 2);
        Offer memory offer = makeSellOffer(initial.market, 2e18, MAX_TICK / 2);
        vm.expectRevert(IMidnightAdapter.SellRateTooHigh.selector);
        directTake(offer);
    }

    /// forge-config: default.isolate = true
    function testEagerLossAllowedDiscountedSale() public {
        Offer memory initial = freshPosition(MAX_TICK);
        deal(address(loanToken), address(realVault), 6e18);
        setMaxSellRate(initial.market, uint256(1e18).mulDivUp(1, 7 days));
        directTake(makeSellOffer(initial.market, 4e18, MAX_TICK / 2));
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
            address(adapter), abi.encodeCall(IAdapter.realAssets, ()), IMidnightAdapter.OtherSellInProgress.selector
        );
        callback.push(
            address(realVault),
            abi.encodeCall(IVaultV2.accrueInterest, ()),
            IMidnightAdapter.OtherSellInProgress.selector
        );
        callback.push(
            address(realVault),
            abi.encodeCall(realVault.deposit, (1e18, recipient)),
            IMidnightAdapter.OtherSellInProgress.selector
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
            address(adapter), abi.encodeCall(IAdapter.realAssets, ()), IMidnightAdapter.OtherSellInProgress.selector
        );
        callback.push(
            address(realVault),
            abi.encodeCall(IVaultV2.accrueInterest, ()),
            IMidnightAdapter.OtherSellInProgress.selector
        );
        callback.push(
            address(realVault),
            abi.encodeCall(realVault.deposit, (1e18, recipient)),
            IMidnightAdapter.OtherSellInProgress.selector
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
        vm.expectRevert(IMidnightAdapter.SellRateTooHigh.selector);
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
                    sign([innerBuy], signerAllocator),
                    innerBuy.maxUnits,
                    address(callback),
                    address(callback),
                    address(0),
                    ""
                )
            ),
            IMidnightAdapter.SellInProgress.selector
        );
        Offer memory innerSell = makeSellOffer(initial.market, 1e18, MAX_TICK);
        callback.push(
            address(midnight),
            abi.encodeCall(
                IMidnight.take,
                (
                    innerSell,
                    sign([innerSell], signerAllocator),
                    innerSell.maxUnits,
                    address(callback),
                    address(0),
                    address(0),
                    ""
                )
            ),
            IMidnightAdapter.SellInProgress.selector
        );
        callback.push(
            address(adapter),
            abi.encodeCall(IMidnightAdapter.withdrawToVault, (initial.market, 0)),
            IMidnightAdapter.SellInProgress.selector
        );
        (Offer memory forced, bytes32 root_) = makeForceDeallocateOffer(initial.market, 1e15);
        bytes memory data = abi.encode(forced, abi.encode(root_, 0, proof([forced])));
        callback.push(
            address(realVault),
            abi.encodeCall(IVaultV2.forceDeallocate, (address(adapter), data, 1e15, address(callback))),
            IMidnightAdapter.SellInProgress.selector
        );
        Offer memory externalBuy = makeExternalOffer(initial.market, true, 1e18, MAX_TICK);
        callback.push(
            address(adapter),
            abi.encodeCall(IMidnightAdapter.take, (externalBuy, "", externalBuy.maxUnits)),
            IMidnightAdapter.SellInProgress.selector
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
                    sign([inner], signerAllocator),
                    inner.maxUnits,
                    address(callback),
                    address(callback),
                    address(0),
                    ""
                )
            ),
            IMidnightAdapter.OtherSellInProgress.selector
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
                    sign([inner], signerAllocator),
                    inner.maxUnits,
                    address(callback),
                    address(callback),
                    address(0),
                    ""
                )
            ),
            accrued ? bytes4(0) : IMidnightAdapter.OtherSellInProgress.selector
        );
        if (accrued) {
            this.accruedCallbackSale(makeSellOffer(initial.market, 4e18, MAX_TICK), callback);
        } else {
            callbackSale(makeSellOffer(initial.market, 4e18, MAX_TICK), callback);
        }
        assertEq(realVault._totalAssets(), 10e18);
        assertEq(backing(), 10e18);
        assertEq(adapter.netCredit(_marketId(initial.market)), 4e18);
        assertEq(adapter.netCredit(_marketId(inner.market)), accrued ? 1e18 : 0);
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
                (inner, sign([inner], signerAllocator), inner.maxUnits, address(callback), address(0), address(0), "")
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
        assertEq(adapter.netCredit(_marketId(initial.market)), 0);
        assertEq(adapter.netCredit(_marketId(second.market)), 0);
    }

    /// forge-config: default.isolate = true
    function testEagerLossDefaultDuringSaleBlocksOnlyUnassistedReads() public {
        Offer memory initial = freshPosition(MAX_TICK);
        EagerLossCallback callback = newCallback();
        callback.push(
            address(this), abi.encodeCall(this.realizeDefault, (initial.market, ORACLE_PRICE_SCALE / 2)), bytes4(0)
        );
        callback.push(
            address(adapter), abi.encodeCall(IAdapter.realAssets, ()), IMidnightAdapter.OtherSellInProgress.selector
        );
        callback.push(
            address(realVault),
            abi.encodeCall(IVaultV2.accrueInterest, ()),
            IMidnightAdapter.OtherSellInProgress.selector
        );
        callback.push(
            address(realVault),
            abi.encodeCall(realVault.deposit, (1e18, recipient)),
            IMidnightAdapter.OtherSellInProgress.selector
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
            address(adapter), abi.encodeCall(IAdapter.realAssets, ()), IMidnightAdapter.OtherSellInProgress.selector
        );
        callback.push(
            address(realVault),
            abi.encodeCall(IVaultV2.accrueInterest, ()),
            IMidnightAdapter.OtherSellInProgress.selector
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
        emit IMidnightAdapter.WithdrawToVault(_marketId(initial.market), withdrawnAssets, withdrawnAssets);
        directTake(offer);

        assertEq(adapter.netCredit(_marketId(initial.market)), sameMarket ? 10e18 : 8e18 - withdrawnAssets);
        assertEq(adapter.netCredit(_marketId(offer.market)), sameMarket ? 10e18 : offer.maxUnits);
        assertEq(adapter.marketIdsLength(), sameMarket || fullWithdrawal ? 1 : 2);
        assertEq(midnight.withdrawable(_marketId(initial.market)), 8e18 - withdrawnAssets);
        assertEq(realVault.allocation(adapter.adapterId()), 10e18);
        assertEq(realVault.allocation(durationId(1 days)), 10e18);
        assertEq(realVault.allocation(durationId(7 days)), sameMarket ? 10e18 : 8e18 - withdrawnAssets);
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

        assertEq(adapter.netCredit(_marketId(initial.market)), sameMarket ? expected : expected - 3e18);
        assertEq(adapter.netCredit(_marketId(offer.market)), sameMarket ? expected : 3e18);
        assertEq(midnight.withdrawable(_marketId(initial.market)), 3e18);
        assertEq(realVault.allocation(adapter.adapterId()), expected);
        assertEq(realVault.allocation(durationId(1 days)), expected);
        assertEq(realVault.allocation(durationId(7 days)), sameMarket ? expected : expected - 3e18);
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

        assertEq(adapter.netCredit(_marketId(initial.market)), 8e18);
        assertEq(adapter.netCredit(_marketId(offer.market)), 1e18);
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

        assertEq(adapter.netCredit(_marketId(initial.market)), 8e18);
        assertEq(adapter.netCredit(_marketId(offer.market)), 0);
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
                    sign([inner], signerAllocator),
                    inner.maxUnits,
                    address(callback),
                    address(callback),
                    address(0),
                    ""
                )
            ),
            succeeds
                ? bytes4(0)
                : (accrued ? IMidnightAdapter.SellInProgress.selector : IMidnightAdapter.OtherSellInProgress.selector)
        );
        if (accrued) {
            this.accruedCallbackSale(makeSellOffer(initial.market, 4e18, MAX_TICK), callback);
        } else {
            callbackSale(makeSellOffer(initial.market, 4e18, MAX_TICK), callback);
        }

        assertEq(adapter.netCredit(_marketId(initial.market)), 4e18);
        assertEq(adapter.netCredit(_marketId(inner.market)), succeeds ? inner.maxUnits : 0);
        assertEq(midnight.withdrawable(_marketId(fundingMarket)), succeeds ? 0 : 1e18);
        assertEq(realVault.allocation(adapter.adapterId()), fundingLocked ? 4e18 : (succeeds ? 6e18 : 5e18));
        assertEq(realVault._totalAssets(), 10e18);
        assertEq(backing(), 10e18);
    }
}
