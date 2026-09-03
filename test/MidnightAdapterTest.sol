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
import {MidnightAdapterSetterRatifier} from "../src/adapters/ratifiers/MidnightAdapterSetterRatifier.sol";
import {
    IMidnightAdapterEcrecoverRatifier
} from "../src/adapters/ratifiers/interfaces/IMidnightAdapterEcrecoverRatifier.sol";
import {IMidnightAdapterSetterRatifier} from "../src/adapters/ratifiers/interfaces/IMidnightAdapterSetterRatifier.sol";
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

contract MidnightAdapterTest is Test {
    using stdStorage for StdStorage;
    using MathLib for uint256;

    IMidnight internal midnight;
    IMidnightAdapterFactory internal factory;
    IMidnightAdapter internal adapter;
    MidnightAdapterEcrecoverRatifier internal ecrecoverRatifier;
    MidnightAdapterSetterRatifier internal setterRatifier;
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

    /// @dev Overridden by subclasses that need the adapter to authorize a specific ratifier at construction time.
    function auctionRatifierAddress() internal virtual returns (address) {
        return address(0);
    }

    function setUp() public virtual {
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

        factory = new MidnightAdapterFactory(allDurations, auctionRatifierAddress());
        adapter = MidnightAdapter(factory.createMidnightAdapter(address(parentVault), address(midnight)));

        ecrecoverRatifier = new MidnightAdapterEcrecoverRatifier();
        setterRatifier = new MidnightAdapterSetterRatifier();
        vm.startPrank(signerAllocator);
        adapter.setIsSubRatifier(address(ecrecoverRatifier), true);
        adapter.setIsSubRatifier(address(setterRatifier), true);
        vm.stopPrank();

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

    /* LAST UPDATE */

    function testLastUpdate() public {
        assertEq(adapter.lastUpdate(), block.timestamp, "set at construction");
        skip(100);
        vm.expectEmit(address(adapter));
        emit IMidnightAdapter.AccrueInterest(0, 0);
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

    function testRatifyIncorrectOfferBadSellSigner(uint256 seed) public {
        vm.setSeed(seed);
        (address otherSigner, uint256 otherSignerKey) = makeAddrAndKey("otherSigner");
        privateKey[otherSigner] = otherSignerKey;
        vm.assume(otherSigner != signerAllocator);
        Offer memory offer = _ratificationSetup();
        bytes32 _root = root(offer);
        bytes memory data = ratifierData(_root, otherSigner);
        vm.expectRevert(IMidnightAdapterEcrecoverRatifier.IncorrectSigner.selector);
        adapter.isRatified(offer, data, taker);
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
        vm.expectRevert(IMidnightAdapterEcrecoverRatifier.IncorrectSigner.selector);
        adapter.isRatified(offer, data, taker);
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

    function testRatifyIncorrectOwner(uint256 seed, address otherMaker) public {
        vm.setSeed(seed);
        Offer memory offer = _ratificationSetup();
        vm.assume(otherMaker != address(adapter));
        offer.maker = otherMaker;
        bytes32 _root = root(offer);
        bytes memory data = ratifierData(_root, signerAllocator);
        vm.expectRevert(IMidnightAdapter.IncorrectOwner.selector);
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
        vm.expectRevert(IMidnightAdapter.NoDebtCreation.selector);
        adapter.isRatified(offer, data, taker);
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

    function testSetIsSubRatifierUnauthorized(address caller, address subRatifier) public {
        vm.assume(!parentVault.isAllocator(caller) && !parentVault.isSentinel(caller));
        vm.prank(caller);
        vm.expectRevert(IMidnightAdapter.NotAuthorized.selector);
        adapter.setIsSubRatifier(subRatifier, true);
        vm.prank(caller);
        vm.expectRevert(IMidnightAdapter.NotAuthorized.selector);
        adapter.setIsSubRatifier(subRatifier, false);
    }

    function testSetIsSubRatifierOK(address subRatifier) public {
        vm.expectEmit(address(adapter));
        emit IMidnightAdapter.SetIsSubRatifier(subRatifier, true);
        vm.prank(signerAllocator);
        adapter.setIsSubRatifier(subRatifier, true);
        assertTrue(adapter.isSubRatifier(subRatifier), "authorized");
        vm.prank(signerAllocator);
        adapter.setIsSubRatifier(subRatifier, false);
        assertFalse(adapter.isSubRatifier(subRatifier), "unauthorized");
    }

    function testSentinelCanOnlyDisableSubRatifier(address sentinel) public {
        vm.assume(sentinel != signerAllocator);
        stdstore.target(address(parentVault)).sig("isSentinel(address)").with_key(sentinel).checked_write(true);
        vm.prank(sentinel);
        vm.expectRevert(IMidnightAdapter.NotAuthorized.selector);
        adapter.setIsSubRatifier(address(ecrecoverRatifier), true);
        vm.prank(sentinel);
        adapter.setIsSubRatifier(address(ecrecoverRatifier), false);
        assertFalse(adapter.isSubRatifier(address(ecrecoverRatifier)), "disabled by sentinel");
    }

    function testRatifySubRatifierUnauthorized(uint256 seed, address subRatifier) public {
        vm.setSeed(seed);
        vm.assume(!adapter.isSubRatifier(subRatifier));
        Offer memory offer = _ratificationSetup();
        vm.expectRevert(IMidnightAdapter.SubRatifierUnauthorized.selector);
        adapter.isRatified(offer, abi.encode(subRatifier, bytes("")), taker);
    }

    function testSetterRatifyNotRatified(uint256 seed) public {
        vm.setSeed(seed);
        Offer memory offer = _ratificationSetup();
        bytes memory data = abi.encode(root(offer), 0, proof([offer]));
        vm.expectRevert(IMidnightAdapterSetterRatifier.NotRatified.selector);
        setterRatifier.isRatified(offer, data, taker);
    }

    function testSetterRatifyOK(uint256 seed) public {
        vm.setSeed(seed);
        Offer memory offer = _ratificationSetup();
        bytes32 _root = root(offer);
        vm.expectEmit(address(setterRatifier));
        emit IMidnightAdapterSetterRatifier.SetIsRootRatified(signerAllocator, address(adapter), _root, true);
        vm.prank(signerAllocator);
        setterRatifier.setIsRootRatified(address(adapter), _root, true);
        assertTrue(setterRatifier.isRootRatified(address(adapter), _root), "root ratified");
        bytes memory data = abi.encode(_root, 0, proof([offer]));
        assertEq(setterRatifier.isRatified(offer, data, taker), CALLBACK_SUCCESS, "callback success");
    }

    function testSetterUnratifyBySentinel(uint256 seed, address sentinel) public {
        vm.setSeed(seed);
        vm.assume(sentinel != signerAllocator);
        stdstore.target(address(parentVault)).sig("isSentinel(address)").with_key(sentinel).checked_write(true);
        Offer memory offer = _ratificationSetup();
        bytes32 _root = root(offer);
        vm.prank(signerAllocator);
        setterRatifier.setIsRootRatified(address(adapter), _root, true);
        vm.prank(sentinel);
        vm.expectRevert(IMidnightAdapterSetterRatifier.NotAuthorized.selector);
        setterRatifier.setIsRootRatified(address(adapter), _root, true);
        vm.prank(sentinel);
        setterRatifier.setIsRootRatified(address(adapter), _root, false);
        bytes memory data = abi.encode(_root, 0, proof([offer]));
        vm.expectRevert(IMidnightAdapterSetterRatifier.NotRatified.selector);
        setterRatifier.isRatified(offer, data, taker);
    }

    function testSetterRatifierTake() public {
        Offer memory offer = makeBuyOffer(30 days, 1e18, discountTick);
        midnight.supplyCollateral(offer.market, 0, offer.maxUnits, taker);
        midnight.supplyCollateral(offer.market, 1, offer.maxUnits, taker);
        bytes memory data = abi.encode(address(setterRatifier), abi.encode(root(offer), 0, proof([offer])));
        vm.prank(taker);
        vm.expectRevert(IMidnightAdapterSetterRatifier.NotRatified.selector);
        midnight.take(offer, data, offer.maxUnits, taker, taker, address(0), "");
        vm.prank(signerAllocator);
        setterRatifier.setIsRootRatified(address(adapter), root(offer), true);
        uint256 vaultBalanceBefore = loanToken.balanceOf(address(parentVault));
        vm.prank(taker);
        midnight.take(offer, data, offer.maxUnits, taker, taker, address(0), "");
        uint256 paid = vaultBalanceBefore - loanToken.balanceOf(address(parentVault));
        assertGt(paid, 0, "paid");
        assertGe(adapter.realAssets(), paid, "accounted");
    }

    function testRogueSubRatifierCannotBypassShapeChecks() public {
        address attacker = makeAddr("attacker");
        vm.prank(signerAllocator);
        adapter.setIsSubRatifier(address(this), true);
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
        vm.prank(taker);
        vm.expectRevert(IMidnightAdapter.NoDebtCreation.selector);
        midnight.take(offer, rogueData, offer.maxUnits, taker, address(0), address(0), "");
        offer.reduceOnly = true;

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
        adapter.setIsSubRatifier(address(ecrecoverRatifier), false);
        vm.prank(taker);
        vm.expectRevert(IMidnightAdapter.SubRatifierUnauthorized.selector);
        midnight.take(offer, data, offer.maxUnits, taker, taker, address(0), "");

        vm.prank(signerAllocator);
        adapter.setIsSubRatifier(address(ecrecoverRatifier), true);
        vm.prank(taker);
        midnight.take(offer, data, offer.maxUnits, taker, taker, address(0), "");
        assertGt(adapter.totalAssets(), 0, "position opened");
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
        vm.prank(otherAllocator);
        otherAdapter.setIsSubRatifier(address(ecrecoverRatifier), true);
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
        vm.prank(signerAllocator);
        vm.expectRevert(IMidnightAdapterSetterRatifier.NotAuthorized.selector);
        setterRatifier.setIsRootRatified(address(otherAdapter), root(offerB), true);

        // Canceling A's root value on B does not affect A.
        vm.prank(otherAllocator);
        ecrecoverRatifier.cancelRoot(address(otherAdapter), root(offerA));
        vm.prank(taker);
        midnight.take(offerA, sign([offerA], signerAllocator), offerA.maxUnits, taker, taker, address(0), "");
        assertGt(adapter.totalAssets(), 0, "A position opened");

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
        assertGt(otherAdapter.totalAssets(), 0, "B position opened");
    }

    function testGarbageSubRatifierRatifierFailed() public {
        GarbageSubRatifier garbage = new GarbageSubRatifier();
        vm.prank(signerAllocator);
        adapter.setIsSubRatifier(address(garbage), true);
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

    function testSetIsRootRatifiedUnauthorized(address caller, bytes32 _root) public {
        vm.assume(!parentVault.isAllocator(caller) && !parentVault.isSentinel(caller));
        vm.prank(caller);
        vm.expectRevert(IMidnightAdapterSetterRatifier.NotAuthorized.selector);
        setterRatifier.setIsRootRatified(address(adapter), _root, true);
        vm.prank(caller);
        vm.expectRevert(IMidnightAdapterSetterRatifier.NotAuthorized.selector);
        setterRatifier.setIsRootRatified(address(adapter), _root, false);
    }

    function testAllocatorCanUnratify(bytes32 _root) public {
        vm.startPrank(signerAllocator);
        setterRatifier.setIsRootRatified(address(adapter), _root, true);
        setterRatifier.setIsRootRatified(address(adapter), _root, false);
        vm.stopPrank();
        assertFalse(setterRatifier.isRootRatified(address(adapter), _root), "unratified");
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
        market.collateralParams = collateralParams;
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

        // Duration ids come from the stored duration count: none for a maturity that was never bought.
        assertEq(ids.length, 1 + market.collateralParams.length * 2);
    }

    function testIdsDurations(uint256 durationIndex, uint256 elapsed) public {
        durationIndex = bound(durationIndex, 0, allDurations.length - 1);
        uint256 duration = allDurations[durationIndex];
        elapsed = bound(elapsed, 0, duration);
        Offer memory offer = buy(duration, 1e18);
        uint256 fixedIds = 1 + offer.market.collateralParams.length * 2;

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

    function testOnBuyRemovesAndReinsertsMaturity() public {
        uint256 t0 = block.timestamp;
        buy(1 days, 1e18);
        Offer memory offer = buy(7 days, 1e18);
        buy(30 days, 1e18);
        bytes32 marketId = _marketId(offer.market);
        setMidnightCredit(marketId, address(adapter), 0);

        // Buying again books the full loss, which empties the maturity, then adds the bought net credit back.
        offer.group = bytes32("second buy");
        midnight.supplyCollateral(offer.market, 0, 1e18, taker);
        midnight.supplyCollateral(offer.market, 1, 1e18, taker);
        vm.expectEmit(address(adapter));
        emit IMidnightAdapter.RemoveMaturity(offer.market.maturity);
        vm.expectEmit(address(adapter));
        emit IMidnightAdapter.InsertMaturity(offer.market.maturity);
        vm.expectEmit(address(adapter));
        emit IMidnightAdapter.Buy(marketId, 1e18, 1e18, 1e18);
        take(offer);

        (uint128 netCredit,) = adapter._markets(marketId);
        assertEq(netCredit, 1e18, "netCredit");
        assertEq(adapter.totalAssets(), 3e18, "totalAssets");
        assertEq(adapter.pendingMaturitiesLength(), 3, "pendingMaturitiesLength");
        assertPendingMaturities([t0 + 1 days, t0 + 7 days, t0 + 30 days]);
    }

    function testSellClearsFirstMaturityAndReactivatesSlot() public {
        checkSellClearsMaturityAndReactivatesSlot(0);
    }

    function testSellClearsMiddleMaturityAndReactivatesSlot() public {
        checkSellClearsMaturityAndReactivatesSlot(25);
    }

    function testSellClearsLastMaturityAndReactivatesSlot() public {
        checkSellClearsMaturityAndReactivatesSlot(49);
    }

    function checkSellClearsMaturityAndReactivatesSlot(uint256 soldIndex) internal {
        Offer memory soldOffer;
        for (uint256 i = 0; i < 50; i++) {
            Offer memory offer = buy(1 days + i, 1e18);
            if (i == soldIndex) soldOffer = offer;
        }
        assertEq(adapter.pendingMaturitiesLength(), 50, "pendingMaturitiesLength before");

        parentVault.setTotalAssets(1e18);
        sell(soldOffer.market, 1e18);

        assertEq(adapter.pendingMaturitiesLength(), 49, "pendingMaturitiesLength after");
        for (uint256 i = 0; i < 49; i++) {
            assertNotEq(adapter.pendingMaturities(i), soldOffer.market.maturity, "sold maturity removed");
        }

        buy(60 days, 1e18);

        assertEq(adapter.pendingMaturitiesLength(), 50, "pendingMaturitiesLength final");
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
        stdstore.target(address(midnight))
            .sig("credit(bytes32,address)")
            .with_key(marketId)
            .with_key(address(adapter))
            .checked_write(units - loss);

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

    function testSetSkipBufferCheckUnauthorized(address caller) public {
        vm.assume(caller != curator);
        vm.prank(caller);
        vm.expectRevert(IMidnightAdapter.NotAuthorized.selector);
        adapter.setSkipBufferCheck(true);
    }

    function testOnSellBufferCheckSkipped() public {
        deal(address(loanToken), address(parentVault), 1e18);
        Offer memory offer = buy(0, 1e18);
        parentVault.setTotalAssets(1e18);

        vm.prank(curator);
        vm.expectEmit(address(adapter));
        emit IMidnightAdapter.SetSkipBufferCheck(true);
        adapter.setSkipBufferCheck(true);
        assertTrue(adapter.skipBufferCheck());

        sellUnits(offer.market, 1e18, MAX_TICK - 4);

        (uint128 marketNetCredit,) = adapter._markets(_marketId(offer.market));
        assertEq(marketNetCredit, 0, "sold below par with no buffer");
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

    // Same buffer check, reached through the allocator take path: taking a buy offer makes the adapter sell,
    // below par here, dropping the vault's real assets under its reported total.
    function testTakeBufferTooLowReverts() public {
        deal(address(loanToken), address(parentVault), 1e18);
        Offer memory offer = buy(0, 1e18);
        parentVault.setTotalAssets(1e18);

        Offer memory buyOffer = makeExternalOffer(offer.market, true, 1e18, MAX_TICK - 4);
        vm.expectRevert(IMidnightAdapter.BufferTooLow.selector);
        vm.prank(signerAllocator);
        adapter.take(buyOffer, "", 1e18);
    }

    function testTakeBufferBigEnough() public {
        uint256 loss = 1e18 - TickLib.tickToPrice(MAX_TICK - 4);

        deal(address(loanToken), address(parentVault), 1e18);
        Offer memory offer = buy(0, 1e18);
        extraAssetsAdapter.setRealAssets(loss);
        parentVault.setTotalAssets(1e18);

        Offer memory buyOffer = makeExternalOffer(offer.market, true, 1e18, MAX_TICK - 4);
        vm.prank(signerAllocator);
        adapter.take(buyOffer, "", 1e18);

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
        assertEq(adapter.totalAssets(), 2e18, "totalAssets");
        assertEq(adapter.pendingMaturitiesLength(), 0, "pendingMaturitiesLength");
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

    /* ACCRUAL */

    function testAccrueInterestLinear() public {
        uint256 duration = 30 days;
        uint256 vaultBalanceBefore = loanToken.balanceOf(address(parentVault));
        Offer memory offer = buy(duration, 1e18, discountTick);
        uint256 paid = vaultBalanceBefore - loanToken.balanceOf(address(parentVault));
        uint256 interest = offer.maxUnits - paid;
        assertGt(interest, 0, "bought at a discount");

        // The growth is an integer per second, the remainder is credited at buy time.
        uint256 valueAtBuy = paid + interest % duration;
        assertEq(adapter.realAssets(), valueAtBuy, "at buy");
        skip(duration / 3);
        assertEq(adapter.realAssets(), valueAtBuy + (interest / duration) * (duration / 3), "a third of the way");
        skip(2 * duration / 3);
        assertEq(adapter.realAssets(), offer.maxUnits, "net credit at maturity");
        skip(365 days);
        assertEq(adapter.realAssets(), offer.maxUnits, "flat after maturity");
    }

    function testAccrueInterestPastAllMaturities() public {
        Offer memory offerA = buy(7 days, 1e18, discountTick);
        Offer memory offerB = buy(30 days, 2e18, discountTick);
        Offer memory offerC = buy(90 days, 3e18, discountTick);
        skip(100 days);

        adapter.accrueInterest();

        assertEq(adapter.totalAssets(), offerA.maxUnits + offerB.maxUnits + offerC.maxUnits, "sum of net credits");
        assertEq(adapter.currentGrowth(), 0, "currentGrowth");
        assertEq(adapter.pendingMaturitiesLength(), 0, "pendingMaturitiesLength");
        assertPendingMaturitiesEmpty();
    }

    function testSellBeforeMaturityRemovesLinearValue() public {
        uint256 duration = 30 days;
        Offer memory offer = buy(duration, 1e18, discountTick);
        skip(duration / 2);
        uint256 valueBefore = adapter.realAssets();

        sell(offer.market, offer.maxUnits / 2);

        // The growth is an integer per second, so the rounding is bounded by the duration.
        assertApproxEqAbs(adapter.realAssets(), valueBefore / 2, duration, "half the value is removed");
        skip(duration / 2);
        assertEq(adapter.realAssets(), offer.maxUnits - offer.maxUnits / 2, "the rest reaches its net credit");
    }

    function testSellAllBeforeMaturity() public {
        Offer memory offer = buy(30 days, 1e18, discountTick);
        skip(10 days);
        deal(address(loanToken), taker, offer.maxUnits);

        sell(offer.market, offer.maxUnits);

        assertEq(adapter.totalAssets(), 0, "totalAssets");
        assertEq(adapter.currentGrowth(), 0, "currentGrowth");
        assertEq(adapter.pendingMaturitiesLength(), 0, "pendingMaturitiesLength");
        assertPendingMaturitiesEmpty();
    }

    function testLossBeforeMaturityRemovesLinearValue() public {
        uint256 duration = 30 days;
        Offer memory offer = buy(duration, 1e18, discountTick);
        bytes32 marketId = _marketId(offer.market);
        skip(duration / 2);
        uint256 valueBefore = adapter.realAssets();

        uint256 loss = offer.maxUnits / 2;
        setMidnightCredit(marketId, address(adapter), offer.maxUnits - loss);
        new MidnightLossRealizer(address(midnight)).realizeLoss(adapter, offer.market);

        assertApproxEqAbs(adapter.realAssets(), valueBefore / 2, duration, "half the value is lost");
        skip(duration / 2);
        assertEq(adapter.realAssets(), offer.maxUnits - loss, "the rest reaches its net credit");
    }

    /* FEES */

    function testContinuousFeeIsNotALoss() public {
        midnight.setDefaultContinuousFee(address(loanToken), MAX_CONTINUOUS_FEE);
        uint256 duration = 30 days;
        Offer memory offer = buy(duration, 1e18, discountTick);
        bytes32 marketId = _marketId(offer.market);

        uint256 pendingFee = midnight.pendingFee(marketId, address(adapter));
        assertGt(pendingFee, 0, "pendingFee");
        (uint128 netCredit,) = adapter._markets(marketId);
        assertEq(netCredit, offer.maxUnits - pendingFee, "net credit excludes the pending fee");

        // The fee accrues out of the credit and of the pending fee alike, so the net credit does not move.
        skip(duration / 2);
        uint256 valueBefore = adapter.realAssets();
        new MidnightLossRealizer(address(midnight)).realizeLoss(adapter, offer.market);
        assertLt(midnight.pendingFee(marketId, address(adapter)), pendingFee, "fee accrued");
        (uint128 netCreditAfter,) = adapter._markets(marketId);
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

    function testForceDeallocateWithSettlementFee() public {
        for (uint256 i = 0; i <= 6; i++) {
            midnight.setDefaultSettlementFee(address(loanToken), i, 10 * CBP);
        }
        Offer memory offer = buy(7 days, 1e18);
        skip(1);
        uint256 vaultBalanceBefore = loanToken.balanceOf(address(parentVault));

        forceDeallocate(offer.market, 0.5e18);

        assertEq(loanToken.balanceOf(address(parentVault)), vaultBalanceBefore + 0.5e18, "vault balance");
        // The fee is paid by the seller, so more than 0.5e18 of net credit is sold.
        (uint128 netCredit,) = adapter._markets(_marketId(offer.market));
        assertLt(netCredit, 0.5e18, "netCredit");
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

        (uint128 netCredit,) = adapter._markets(_marketId(offer.market));
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

    function testForceDeallocateWithoutRole() public {
        Offer memory boughtOffer = buy(7 days, 1e18);
        skip(1);

        // Simulate the adapter having no role: any vault.deallocate call from the adapter reverts.
        vm.mockCallRevert(address(parentVault), abi.encodeWithSelector(VaultV2Mock.deallocate.selector), "no role");

        forceDeallocate(boughtOffer.market, 0.5e18);

        assertEq(parentVault.allocation(durationId(1 days)), 0.5e18, "1 day");
        assertEq(parentVault.allocation(durationId(7 days)), 0.5e18, "7 days, stale");
        (uint128 marketNetCredit,) = adapter._markets(_marketId(boughtOffer.market));
        assertEq(marketNetCredit, 0.5e18, "netCredit");

        vm.expectRevert(bytes("no role"));
        adapter.updateDurationCaps(boughtOffer.market.maturity);
    }

    /// forge-config: default.isolate = true
    /// @dev Runs on a real VaultV2, with a non-zero penalty, fees and maxRate, and with the adapter's allocator role
    /// revoked before the exit.
    function testForceDeallocateRealVaultWithPenalty() public virtual {
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
        (uint128 marketNetCredit,) = adapter._markets(_marketId(offer.market));
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
        assertEq(adapter.totalAssets(), 1e18, "adapter totalAssets after buy");

        skip(1);

        // Sell 0.5e18 credit by taking an external buy offer, proceeds forwarded to the vault.
        Offer memory buyOffer = makeExternalOffer(market, true, 0.5e18, MAX_TICK);
        vm.prank(signerAllocator);
        adapter.take(buyOffer, "", uint256(buyOffer.maxUnits));

        (uint128 marketNetCredit,) = adapter._markets(marketId);
        assertEq(marketNetCredit, 0.5e18, "netCredit after sell");
        assertEq(realVault.allocation(adapter.adapterId()), 0.5e18, "allocation after sell");
        assertEq(loanToken.balanceOf(address(realVault)), 9.5e18, "proceeds back in the vault");
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

    function testWithdrawToVaultUnauthorized(address nonAllocator) public {
        vm.assume(!parentVault.isAllocator(nonAllocator) && !parentVault.isSentinel(nonAllocator));
        Market memory market = storedOffer.market;
        vm.prank(nonAllocator);
        vm.expectRevert(IMidnightAdapter.NotAuthorized.selector);
        adapter.withdrawToVault(market, 0);
    }

    function testWithdrawToVaultBySentinel(address sentinel) public {
        vm.assume(sentinel != signerAllocator);
        stdstore.target(address(parentVault)).sig("isSentinel(address)").with_key(sentinel).checked_write(true);
        Offer memory boughtOffer = buy(7 days, 1e18);

        vm.prank(sentinel);
        adapter.withdrawToVault(boughtOffer.market, 0);
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
        vm.expectEmit(address(adapter));
        emit IMidnightAdapter.WithdrawToVault(marketId, withdrawAmount, withdrawAmount);
        vm.prank(signerAllocator);
        adapter.withdrawToVault(boughtOffer.market, withdrawAmount);

        (uint128 creditAfter,) = adapter._markets(marketId);
        assertEq(creditAfter, creditBefore - withdrawAmount, "netCredit");
        assertEq(adapter.totalAssets(), creditBefore - withdrawAmount, "totalAssets");
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
        (uint128 netCredit,) = adapter._markets(marketId);
        assertApproxEqAbs(netCredit, 0.2e18, 1, "netCredit");
        assertApproxEqAbs(adapter.totalAssets(), 0.2e18, 1, "totalAssets");
        assertApproxEqAbs(parentVault.allocation(adapter.adapterId()), 0.2e18, 1, "allocation");
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
        offer.maxUnits = uint128(assets * 1e18 / TickLib.tickToPrice(tick));
        offer.expiry = block.timestamp;
        offer.callback = address(adapter);
        offer.callbackData = hex"";
    }

    function take(Offer memory offer) internal {
        vm.prank(taker);
        midnight.take(offer, sign([offer], signerAllocator), offer.maxUnits, taker, taker, address(0), "");
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
        vm.prank(taker);
        midnight.take(offer, sign([offer], signerAllocator), offer.maxUnits, taker, address(0), address(0), "");
    }

    function sellUnits(Market memory market, uint256 units, uint256 tick) internal {
        Offer memory offer = makeSellOffer(market, units, tick);
        vm.prank(taker);
        midnight.take(offer, sign([offer], signerAllocator), offer.maxUnits, taker, address(0), address(0), "");
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
        offer.maxUnits =
            uint128(TakeAmountsLib.sellerAssetsToUnits(address(midnight), _marketId(market), offer, assets));
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
    function makeExternalOffer(Market memory market, bool buy, uint256 assets, uint256 tick)
        internal
        returns (Offer memory offer)
    {
        address maker = makeAddr(buy ? "externalBuyer" : "externalSeller");
        vm.prank(maker);
        midnight.setIsAuthorized(address(this), true, maker);

        offer = storedOffer;
        offer.market = market;
        offer.buy = buy;
        offer.maker = maker;
        offer.tick = tick;
        offer.maxUnits = uint128(assets * 1e18 / TickLib.tickToPrice(tick));
        offer.expiry = block.timestamp;
        offer.callback = address(0);
        offer.receiverIfMakerIsSeller = buy ? address(0) : maker;
        offer.ratifier = address(this);
        offer.group = bytes32(vm.randomUint());

        if (buy) {
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
        vm.prank(signerAllocator);
        adapter.setIsSubRatifier(address(ecrecoverRatifier), true);
        submitAndCall(realVault, abi.encodeCall(IVaultV2.setForceDeallocatePenalty, (address(adapter), 0.02e18)));
        submitAndCall(realVault, abi.encodeCall(IVaultV2.setPerformanceFeeRecipient, (recipient)));
        submitAndCall(realVault, abi.encodeCall(IVaultV2.setManagementFeeRecipient, (recipient)));
        submitAndCall(realVault, abi.encodeCall(IVaultV2.setPerformanceFee, (0.1e18)));
        submitAndCall(realVault, abi.encodeCall(IVaultV2.setManagementFee, (1e9)));
        vm.prank(signerAllocator);
        realVault.setMaxRate(1e18 / uint256(365 days));

        bytes[] memory idDatas = new bytes[](7);
        idDatas[0] = abi.encode("this", address(adapter));
        idDatas[1] = abi.encode("collateralToken", storedCollaterals[0].token);
        idDatas[2] = abi.encode(
            "collateral", storedCollaterals[0].token, storedCollaterals[0].oracle, storedCollaterals[0].lltv
        );
        idDatas[3] = abi.encode("collateralToken", storedCollaterals[1].token);
        idDatas[4] = abi.encode(
            "collateral", storedCollaterals[1].token, storedCollaterals[1].oracle, storedCollaterals[1].lltv
        );
        idDatas[5] = abi.encode("duration", uint256(1 days));
        idDatas[6] = abi.encode("duration", uint256(7 days));
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

    /// @dev Returns the concatenation of x and y, sorted lexicographically.
    function sort(bytes32 x, bytes32 y) internal pure returns (bytes memory) {
        return x < y ? abi.encodePacked(x, y) : abi.encodePacked(y, x);
    }
}
