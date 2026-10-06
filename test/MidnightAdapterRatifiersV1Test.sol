// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Morpho Association
pragma solidity ^0.8.0;

import {Test} from "../lib/forge-std/src/Test.sol";
import {IMidnight, Market, CollateralParams, Offer} from "../lib/midnight/src/interfaces/IMidnight.sol";
import {CALLBACK_SUCCESS, DEFAULT_TICK_SPACING} from "../lib/midnight/src/libraries/ConstantsLib.sol";
import {TickLib, MAX_TICK} from "../lib/midnight/src/libraries/TickLib.sol";
import {HashLib} from "../lib/midnight/src/ratifiers/libraries/HashLib.sol";
import {Signature} from "../lib/midnight/src/ratifiers/interfaces/IEcrecoverRatifier.sol";
import {
    IRatifiersV1Common,
    SET_IS_ROOT_RATIFIED_SUCCESS
} from "../lib/midnight/src/ratifiers/interfaces/IRatifiersV1Common.sol";
import {MidnightAdapterPriceRatifierV1} from "../src/adapters/ratifiers/MidnightAdapterPriceRatifierV1.sol";
import {MidnightAdapterRateRatifierV1} from "../src/adapters/ratifiers/MidnightAdapterRateRatifierV1.sol";
import {
    IMidnightAdapterPriceRatifierV1,
    EIP712_DOMAIN_TYPEHASH
} from "../src/adapters/ratifiers/interfaces/IMidnightAdapterPriceRatifierV1.sol";
import {IMidnightAdapterRateRatifierV1} from "../src/adapters/ratifiers/interfaces/IMidnightAdapterRateRatifierV1.sol";
import {IMidnightAdapter, IMidnightAdapterBase} from "../src/adapters/interfaces/IMidnightAdapter.sol";
import {MidnightAdapter} from "../src/adapters/MidnightAdapter.sol";
import {ERC20Mock} from "./mocks/ERC20Mock.sol";
import {OracleMock} from "../lib/morpho-blue/src/mocks/OracleMock.sol";
import {IdLib} from "../lib/midnight/src/libraries/IdLib.sol";
import {VaultV2Mock} from "./mocks/VaultV2Mock.sol";

abstract contract MidnightAdapterRatifiersV1Test is Test {
    IRatifiersV1Common internal ratifier;
    VaultV2Mock internal vault;
    address internal maker;
    address internal allocator;
    uint256 internal allocatorKey;
    address internal sentinel;
    uint256 internal sentinelKey;
    address internal taker;
    Offer internal offer;

    function isRate() internal pure virtual returns (bool);

    function setUp() public {
        (allocator, allocatorKey) = makeAddrAndKey("allocator");
        (sentinel, sentinelKey) = makeAddrAndKey("sentinel");
        maker = makeAddr("adapter");
        taker = makeAddr("taker");
        vault = new VaultV2Mock(address(0), address(this), address(this), allocator, sentinel);
        vm.mockCall(maker, abi.encodeCall(IMidnightAdapterBase.parentVault, ()), abi.encode(address(vault)));
        ratifier = isRate()
            ? IRatifiersV1Common(address(new MidnightAdapterRateRatifierV1()))
            : IRatifiersV1Common(address(new MidnightAdapterPriceRatifierV1()));
        offer.maker = maker;
        offer.ratifier = maker;
        offer.callback = maker;
        offer.buy = true;
        offer.tick = MAX_TICK;
        offer.market.chainId = block.chainid;
        offer.market.maturity = block.timestamp + 365 days;
        offer.expiry = offer.market.maturity;
    }

    function leaf(Offer memory _offer, uint256 rate, address allowedTaker) external pure returns (bytes32) {
        return isRate()
            ? HashLib.hashRateRatifierV1Offer(_offer, rate, allowedTaker)
            : HashLib.hashPriceRatifierV1Offer(_offer, allowedTaker);
    }

    function data(bytes32 root, uint256 index, bytes32[] memory proof, uint256 rate, address allowedTaker)
        internal
        pure
        returns (bytes memory)
    {
        return isRate()
            ? abi.encode(root, index, proof, rate, allowedTaker)
            : abi.encode(root, index, proof, allowedTaker);
    }

    function setRoot(bytes32 root, bool status) internal {
        vm.prank(allocator);
        ratifier.setIsRootRatified(maker, root, status);
    }

    function signature(bytes32 root, bool status, uint128 nonce, uint256 deadline, uint256 key)
        internal
        view
        returns (Signature memory sig)
    {
        bytes32 typeHash =
            isRate() ? HashLib.rateRatifierV1OfferTreeTypeHash(0) : HashLib.priceRatifierV1OfferTreeTypeHash(0);
        bytes32 structHash = keccak256(abi.encode(typeHash, maker, root, status, nonce, deadline));
        bytes32 domain = keccak256(abi.encode(EIP712_DOMAIN_TYPEHASH, block.chainid, address(ratifier)));
        (sig.v, sig.r, sig.s) = vm.sign(key, keccak256(bytes.concat("\x19\x01", domain, structHash)));
    }

    function submitSignature(bytes32 root, bool status, uint128 nonce, uint256 deadline, Signature memory sig)
        internal
        returns (bytes32)
    {
        return ratifier.setIsRootRatifiedWithSig(maker, root, 0, status, nonce, deadline, sig.v, sig.r, sig.s);
    }

    function testDomainSeparator() public view {
        assertEq(
            IMidnightAdapterPriceRatifierV1(address(ratifier)).DOMAIN_SEPARATOR(),
            keccak256(abi.encode(EIP712_DOMAIN_TYPEHASH, block.chainid, address(ratifier)))
        );
    }

    function testAllocatorSetRoot(bytes32 root, bool status) public {
        vm.expectEmit(address(ratifier));
        emit IMidnightAdapterPriceRatifierV1.SetIsRootRatified(allocator, maker, root, status);
        vm.prank(allocator);
        assertEq(ratifier.setIsRootRatified(maker, root, status), SET_IS_ROOT_RATIFIED_SUCCESS);
        assertEq(ratifier.isRootRatified(maker, root), status);
        assertEq(ratifier.rootNonce(maker, root), 0);
    }

    function testUnauthorizedSetter(address caller, bool status) public {
        vm.assume(caller != allocator && caller != sentinel);
        vm.prank(caller);
        vm.expectRevert(IMidnightAdapterPriceRatifierV1.Unauthorized.selector);
        ratifier.setIsRootRatified(maker, bytes32(0), status);
    }

    function testSentinelCanOnlyUnratify() public {
        bytes32 root = this.leaf(offer, 0, address(0));
        setRoot(root, true);
        vm.prank(sentinel);
        ratifier.setIsRootRatified(maker, root, false);
        assertFalse(ratifier.isRootRatified(maker, root));
        vm.prank(sentinel);
        vm.expectRevert(IMidnightAdapterPriceRatifierV1.Unauthorized.selector);
        ratifier.setIsRootRatified(maker, root, true);
    }

    function testUnratifiedRoot() public {
        bytes memory ratifierData = data(this.leaf(offer, 0, address(0)), 0, new bytes32[](0), 0, address(0));
        vm.expectRevert(IMidnightAdapterPriceRatifierV1.NotRatified.selector);
        ratifier.isRatified(offer, ratifierData, taker);
    }

    function testAllowedTakerAndTampering() public {
        bytes32 root = this.leaf(offer, 0, taker);
        setRoot(root, true);
        bytes memory ratifierData = data(root, 0, new bytes32[](0), 0, taker);
        assertEq(ratifier.isRatified(offer, ratifierData, taker), CALLBACK_SUCCESS);
        vm.expectRevert(IMidnightAdapterPriceRatifierV1.UnauthorizedTaker.selector);
        ratifier.isRatified(offer, ratifierData, allocator);
        ratifierData = data(root, 0, new bytes32[](0), 0, address(0));
        vm.expectRevert(IMidnightAdapterPriceRatifierV1.InvalidProof.selector);
        ratifier.isRatified(offer, ratifierData, allocator);
    }

    function testMerkleProofAndLeafIndex() public {
        Offer memory sibling = offer;
        sibling.expiry += 1;
        bytes32 root = HashLib.hashNode(this.leaf(offer, 0, address(0)), this.leaf(sibling, 0, address(0)));
        setRoot(root, true);
        bytes32[] memory proof = new bytes32[](1);
        proof[0] = this.leaf(offer, 0, address(0));
        bytes memory ratifierData = data(root, 1, proof, 0, address(0));
        assertEq(ratifier.isRatified(sibling, ratifierData, taker), CALLBACK_SUCCESS);
        ratifierData = data(root, 0, proof, 0, address(0));
        vm.expectRevert(IMidnightAdapterPriceRatifierV1.InvalidProof.selector);
        ratifier.isRatified(sibling, ratifierData, taker);
        ratifierData = data(root, 2, proof, 0, address(0));
        vm.expectRevert(HashLib.LeafIndexOutOfRange.selector);
        ratifier.isRatified(sibling, ratifierData, taker);
    }

    function testRevocationBlocksOffer() public {
        bytes32 root = this.leaf(offer, 0, address(0));
        bytes memory ratifierData = data(root, 0, new bytes32[](0), 0, address(0));
        setRoot(root, true);
        assertEq(ratifier.isRatified(offer, ratifierData, taker), CALLBACK_SUCCESS);
        setRoot(root, false);
        vm.expectRevert(IMidnightAdapterPriceRatifierV1.NotRatified.selector);
        ratifier.isRatified(offer, ratifierData, taker);
    }

    function testRootsArePerAdapter() public {
        address otherMaker = makeAddr("otherAdapter");
        VaultV2Mock otherVault = new VaultV2Mock(address(0), address(this), address(this), taker, sentinel);
        vm.mockCall(otherMaker, abi.encodeCall(IMidnightAdapterBase.parentVault, ()), abi.encode(address(otherVault)));
        bytes32 root = this.leaf(offer, 0, address(0));
        setRoot(root, true);
        vm.prank(allocator);
        vm.expectRevert(IMidnightAdapterPriceRatifierV1.Unauthorized.selector);
        ratifier.setIsRootRatified(otherMaker, root, false);
        vm.prank(taker);
        ratifier.setIsRootRatified(otherMaker, root, false);
        assertTrue(ratifier.isRootRatified(maker, root));
        assertFalse(ratifier.isRootRatified(otherMaker, root));
    }

    function testSignedRatification(bytes32 root, bool status) public {
        Signature memory sig = signature(root, status, 0, block.timestamp, allocatorKey);
        vm.expectEmit(address(ratifier));
        emit IMidnightAdapterPriceRatifierV1.SetIsRootRatifiedWithSig(
            allocator, allocator, maker, root, 0, status, 0, 0
        );
        vm.prank(allocator);
        assertEq(submitSignature(root, status, 0, block.timestamp, sig), SET_IS_ROOT_RATIFIED_SUCCESS);
        assertEq(ratifier.isRootRatified(maker, root), status);
        assertEq(ratifier.rootNonce(maker, root), 1);
    }

    function testSignedRatificationUnauthorizedCaller() public {
        Signature memory sig = signature(bytes32(0), true, 0, block.timestamp, allocatorKey);
        vm.prank(taker);
        vm.expectRevert(IMidnightAdapterPriceRatifierV1.Unauthorized.selector);
        submitSignature(bytes32(0), true, 0, block.timestamp, sig);
        vm.prank(sentinel);
        vm.expectRevert(IMidnightAdapterPriceRatifierV1.Unauthorized.selector);
        submitSignature(bytes32(0), true, 0, block.timestamp, sig);
    }

    function testSignedOfferTree() public {
        Offer memory sibling = offer;
        sibling.expiry += 1;
        bytes32[] memory proof = new bytes32[](1);
        proof[0] = this.leaf(offer, 0, address(0));
        bytes32 root = HashLib.hashNode(proof[0], this.leaf(sibling, 0, taker));
        bytes32 typeHash =
            isRate() ? HashLib.rateRatifierV1OfferTreeTypeHash(1) : HashLib.priceRatifierV1OfferTreeTypeHash(1);
        bytes32 structHash = keccak256(abi.encode(typeHash, maker, root, true, uint128(0), block.timestamp));
        bytes32 domain = keccak256(abi.encode(EIP712_DOMAIN_TYPEHASH, block.chainid, address(ratifier)));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(allocatorKey, keccak256(bytes.concat("\x19\x01", domain, structHash)));
        vm.prank(allocator);
        ratifier.setIsRootRatifiedWithSig(maker, root, 1, true, 0, block.timestamp, v, r, s);
        assertEq(ratifier.isRatified(sibling, data(root, 1, proof, 0, taker), taker), CALLBACK_SUCCESS);
    }

    function testSignedRatificationUnauthorizedSigner() public {
        (, uint256 key) = makeAddrAndKey("unauthorizedSigner");
        Signature memory sig = signature(bytes32(0), true, 0, block.timestamp, key);
        vm.prank(allocator);
        vm.expectRevert(IMidnightAdapterPriceRatifierV1.Unauthorized.selector);
        submitSignature(bytes32(0), true, 0, block.timestamp, sig);
    }

    function testSentinelSignatureCanOnlyUnratify() public {
        setRoot(bytes32(0), true);
        Signature memory sig = signature(bytes32(0), false, 0, block.timestamp, sentinelKey);
        vm.prank(sentinel);
        submitSignature(bytes32(0), false, 0, block.timestamp, sig);
        assertFalse(ratifier.isRootRatified(maker, bytes32(0)));
        sig = signature(bytes32(0), true, 1, block.timestamp, sentinelKey);
        vm.prank(allocator);
        vm.expectRevert(IMidnightAdapterPriceRatifierV1.Unauthorized.selector);
        submitSignature(bytes32(0), true, 1, block.timestamp, sig);
    }

    function testRemovedAllocatorSignatureRejectedButApprovedRootsPersist() public {
        bytes32 root = this.leaf(offer, 0, address(0));
        setRoot(root, true);
        Signature memory sig = signature(root, false, 0, block.timestamp, allocatorKey);
        vm.mockCall(address(vault), abi.encodeWithSignature("isAllocator(address)", allocator), abi.encode(false));
        vm.prank(sentinel);
        vm.expectRevert(IMidnightAdapterPriceRatifierV1.Unauthorized.selector);
        submitSignature(root, false, 0, block.timestamp, sig);
        assertEq(ratifier.isRatified(offer, data(root, 0, new bytes32[](0), 0, address(0)), taker), CALLBACK_SUCCESS);
    }

    function testSignedRatificationDeadlineExpired() public {
        Signature memory sig = signature(bytes32(0), true, 0, block.timestamp - 1, allocatorKey);
        vm.prank(allocator);
        vm.expectRevert(IMidnightAdapterPriceRatifierV1.DeadlineExpired.selector);
        submitSignature(bytes32(0), true, 0, block.timestamp - 1, sig);
    }

    function testSignedRatificationFutureNonce() public {
        Signature memory sig = signature(bytes32(0), true, 1, block.timestamp, allocatorKey);
        vm.prank(allocator);
        vm.expectRevert(IMidnightAdapterPriceRatifierV1.InvalidNonce.selector);
        submitSignature(bytes32(0), true, 1, block.timestamp, sig);
    }

    function testSignatureReplayAndStatusChange() public {
        Signature memory sig = signature(bytes32(0), true, 0, block.timestamp, allocatorKey);
        vm.prank(allocator);
        submitSignature(bytes32(0), true, 0, block.timestamp, sig);
        vm.prank(allocator);
        submitSignature(bytes32(0), true, 0, block.timestamp, sig);
        assertEq(ratifier.rootNonce(maker, bytes32(0)), 1);
        setRoot(bytes32(0), false);
        assertEq(ratifier.rootNonce(maker, bytes32(0)), 1);
        vm.prank(allocator);
        vm.expectRevert(IMidnightAdapterPriceRatifierV1.RatifiedStatusChanged.selector);
        submitSignature(bytes32(0), true, 0, block.timestamp, sig);
    }

    function testInvalidSignature() public {
        Signature memory sig;
        vm.prank(allocator);
        vm.expectRevert(IMidnightAdapterPriceRatifierV1.InvalidSignature.selector);
        submitSignature(bytes32(0), true, 0, block.timestamp, sig);
    }

    function testSignatureCannotCrossChainOrRatifier(bool changeChain) public {
        Signature memory sig = signature(bytes32(0), true, 0, block.timestamp, allocatorKey);
        if (changeChain) {
            vm.chainId(block.chainid + 1);
        } else {
            ratifier = isRate()
                ? IRatifiersV1Common(address(new MidnightAdapterRateRatifierV1()))
                : IRatifiersV1Common(address(new MidnightAdapterPriceRatifierV1()));
        }
        vm.prank(allocator);
        vm.expectRevert(IMidnightAdapterPriceRatifierV1.Unauthorized.selector);
        submitSignature(bytes32(0), true, 0, block.timestamp, sig);
    }

    function testSignedFieldsCannotBeChanged(uint8 field) public {
        field = uint8(bound(field, 0, 5));
        Signature memory sig = signature(bytes32(0), true, 0, block.timestamp, allocatorKey);
        address otherMaker = makeAddr("otherAdapter");
        vm.mockCall(otherMaker, abi.encodeCall(IMidnightAdapterBase.parentVault, ()), abi.encode(address(vault)));
        vm.prank(allocator);
        vm.expectRevert(IMidnightAdapterPriceRatifierV1.Unauthorized.selector);
        ratifier.setIsRootRatifiedWithSig(
            field == 0 ? otherMaker : maker,
            field == 1 ? bytes32(uint256(1)) : bytes32(0),
            field == 2 ? 1 : 0,
            field != 3,
            field == 4 ? 1 : 0,
            field == 5 ? block.timestamp + 1 : block.timestamp,
            sig.v,
            sig.r,
            sig.s
        );
    }
}

contract MidnightAdapterPriceRatifierV1Test is MidnightAdapterRatifiersV1Test {
    function isRate() internal pure override returns (bool) {
        return false;
    }

    function testTickIsCommitted() public {
        bytes32 root = this.leaf(offer, 0, address(0));
        setRoot(root, true);
        offer.tick -= 1;
        bytes memory ratifierData = data(root, 0, new bytes32[](0), 0, address(0));
        vm.expectRevert(IMidnightAdapterPriceRatifierV1.InvalidProof.selector);
        ratifier.isRatified(offer, ratifierData, taker);
    }
}

contract MidnightAdapterRateRatifierV1Test is MidnightAdapterRatifiersV1Test {
    function isRate() internal pure override returns (bool) {
        return true;
    }

    function testRatePriceBoundaries(bool buy, uint256 rate, uint256 duration, uint256 tick) public {
        rate = bound(rate, 0, 1e18);
        duration = bound(duration, 0, 3650 days);
        tick = bound(tick, 0, MAX_TICK);
        offer.buy = buy;
        offer.market.maturity = block.timestamp + duration;
        bytes32 root = this.leaf(offer, rate, address(0));
        setRoot(root, true);
        offer.tick = tick;
        bytes memory ratifierData = data(root, 0, new bytes32[](0), rate, address(0));
        uint256 price = TickLib.tickToPrice(tick);
        bool acceptable = buy ? price * (1e18 + rate * duration) <= 1e36 : price * (1e18 + rate * duration) >= 1e36;
        if (!acceptable) vm.expectRevert(IMidnightAdapterRateRatifierV1.WorsePrice.selector);
        bytes32 result = ratifier.isRatified(offer, ratifierData, taker);
        if (acceptable) assertEq(result, CALLBACK_SUCCESS);
    }

    function testRatePriceChangesWithMaturity() public {
        uint256 rate = uint256(0.1e18) / 365 days;
        bytes32 root = this.leaf(offer, rate, address(0));
        setRoot(root, true);
        bytes memory ratifierData = data(root, 0, new bytes32[](0), rate, address(0));
        vm.expectRevert(IMidnightAdapterRateRatifierV1.WorsePrice.selector);
        ratifier.isRatified(offer, ratifierData, taker);
        vm.warp(offer.market.maturity);
        assertEq(ratifier.isRatified(offer, ratifierData, taker), CALLBACK_SUCCESS);
        skip(1 days);
        assertEq(ratifier.isRatified(offer, ratifierData, taker), CALLBACK_SUCCESS);
    }

    function testRateIsCommitted() public {
        offer.tick = 0;
        bytes32 root = this.leaf(offer, 1, address(0));
        setRoot(root, true);
        bytes memory ratifierData = data(root, 0, new bytes32[](0), 0, address(0));
        vm.expectRevert(IMidnightAdapterRateRatifierV1.InvalidProof.selector);
        ratifier.isRatified(offer, ratifierData, taker);
    }
}

contract MidnightAdapterRateRatifierV1IntegrationTest is Test {
    function testBuyAndSell() public {
        vm.setEvmVersion("osaka");
        IMidnight midnight = IMidnight(deployCode("Midnight.sol:Midnight"));
        midnight.enableLltv(1e18);
        midnight.enableLiquidationCursor(0.25e18);
        ERC20Mock loanToken = new ERC20Mock(18);
        ERC20Mock collateralToken = new ERC20Mock(18);
        OracleMock oracle = new OracleMock();
        oracle.setPrice(1e36);
        VaultV2Mock vault = new VaultV2Mock(address(loanToken), address(this), address(this), address(this), address(0));
        uint256[] memory durations = new uint256[](1);
        durations[0] = 1 days;
        IMidnightAdapter adapter =
            IMidnightAdapter(address(new MidnightAdapter(address(vault), address(midnight), durations)));
        bytes32 durationId = keccak256(abi.encode("duration", address(adapter), durations[0]));
        vault.setRelativeCap(durationId, 1e18);
        vault.setAbsoluteCap(durationId, type(uint128).max);
        adapter.submit(abi.encodeCall(IMidnightAdapterBase.setMaxTtm, (30 days)));
        adapter.setMaxTtm(30 days);
        MidnightAdapterRateRatifierV1 ratifier = new MidnightAdapterRateRatifierV1();
        adapter.setIsSubRatifier(address(ratifier), true);
        deal(address(loanToken), address(vault), 1e24);
        deal(address(loanToken), address(this), 1e24);
        deal(address(collateralToken), address(this), 1e24);
        loanToken.approve(address(midnight), type(uint256).max);
        collateralToken.approve(address(midnight), type(uint256).max);

        CollateralParams[] memory collaterals = new CollateralParams[](1);
        collaterals[0] = CollateralParams(address(collateralToken), 1e18, 0.25e18, address(oracle));
        Offer memory offer;
        offer.market = Market(
            block.chainid,
            address(midnight),
            address(loanToken),
            collaterals,
            block.timestamp + 30 days,
            0,
            address(0),
            address(0)
        );
        offer.buy = true;
        offer.maker = address(adapter);
        offer.callback = address(adapter);
        offer.ratifier = address(adapter);
        offer.tick = TickLib.priceToTick(0.95e18, DEFAULT_TICK_SPACING);
        offer.expiry = offer.market.maturity;
        offer.maxUnits = 1e18;
        offer.continuousFeeCap = type(uint256).max;
        midnight.supplyCollateral(offer.market, 0, offer.maxUnits, address(this));
        take(midnight, ratifier, offer);
        bytes32 marketId = IdLib.toId(offer.market);
        uint256 netCreditBefore = adapter.marketData(marketId).netCredit;
        assertGt(netCreditBefore, 0, "position opened");

        offer.buy = false;
        offer.receiverIfMakerIsSeller = address(adapter);
        offer.group = bytes32("sell");
        offer.tick = MAX_TICK;
        offer.maxUnits = 1e17;
        take(midnight, ratifier, offer);
        assertLt(adapter.marketData(marketId).netCredit, netCreditBefore, "position reduced");
    }

    function take(IMidnight midnight, MidnightAdapterRateRatifierV1 ratifier, Offer memory offer) internal {
        uint256 rate = 1e9;
        bytes32 root = HashLib.hashRateRatifierV1Offer(offer, rate, address(this));
        ratifier.setIsRootRatified(offer.maker, root, true);
        bytes memory data = abi.encode(address(ratifier), abi.encode(root, 0, new bytes32[](0), rate, address(this)));
        midnight.take(
            offer, data, offer.maxUnits, address(this), offer.buy ? address(this) : address(0), address(0), ""
        );
    }
}
