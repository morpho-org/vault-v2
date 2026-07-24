// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Morpho Association
pragma solidity ^0.8.28;

import "../integration/MorphoMarketV1IntegrationTest.sol";

import {BlueAdapterV2PublicAllocator} from "../../src/periphery/BlueAdapterV2PublicAllocator.sol";
import {IBlueAdapterV2PublicAllocator} from "../../src/periphery/interfaces/IBlueAdapterV2PublicAllocator.sol";

contract RejectNative {}

/// @dev The public allocator is specialized to Morpho Market V1 (Morpho Blue) via the Morpho Market V1 adapter (V2).
/// These tests use a real vault + adapter + Morpho Blue markets so that the absolute cap is keyed by the exact
/// per-market vault id (keccak256(abi.encode("this/marketParams", adapter, marketParams))).
contract BlueAdapterV2PublicAllocatorTest is MorphoMarketV1IntegrationTest {
    using MorphoBalancesLib for IMorpho;

    BlueAdapterV2PublicAllocator internal publicAllocator;

    address internal rando = makeAddr("rando");

    // Per-market vault ids (== expectedIds1[2] / expectedIds2[2] from the integration harness).
    bytes32 internal id1;
    bytes32 internal id2;

    function setUp() public override {
        super.setUp();

        id1 = expectedIds1[2];
        id2 = expectedIds2[2];

        publicAllocator = new BlueAdapterV2PublicAllocator(address(factory));

        // Make the public allocator an allocator of the vault (timelocks are 0 at setup).
        vm.prank(curator);
        vault.submit(abi.encodeCall(IVaultV2.setIsAllocator, (address(publicAllocator), true)));
        vault.setIsAllocator(address(publicAllocator), true);
    }

    /* HELPERS */

    // The absolute cap is set by the vault's allocators (inherited role).
    function _setAbsoluteCap(MarketParams memory marketParams, uint256 cap) internal {
        vm.prank(allocator);
        publicAllocator.setAbsoluteCap(address(vault), address(adapter), marketParams, cap);
    }

    function _setCanDeallocate(MarketParams memory marketParams, bool value) internal {
        vm.prank(allocator);
        publicAllocator.setCanDeallocate(address(vault), address(adapter), marketParams, value);
    }

    function _setCanDeallocateFromIdle(bool value) internal {
        vm.prank(allocator);
        publicAllocator.setCanDeallocateFromIdle(address(vault), value);
    }

    // Deposit into the vault and allocate to market1 so there is liquidity to reallocate away from.
    function _seedMarket1(uint256 assets) internal {
        vault.deposit(assets, address(this));
        vm.prank(allocator);
        vault.allocate(address(adapter), abi.encode(marketParams1), assets);
    }

    function _reallocate(uint128 assets) internal {
        vm.prank(rando);
        publicAllocator.reallocate(
            address(vault), address(adapter), marketParams1, address(adapter), marketParams2, assets
        );
    }

    /* SET ABSOLUTE CAP */

    function testSetAbsoluteCap(uint256 cap) public {
        vm.expectEmit();
        emit IBlueAdapterV2PublicAllocator.SetAbsoluteCap(
            allocator, address(vault), address(adapter), marketParams2, cap
        );
        _setAbsoluteCap(marketParams2, cap);
        assertEq(publicAllocator.absoluteCap(address(vault), id2), cap);
    }

    function testSetAbsoluteCapUnauthorized(address caller, uint256 cap) public {
        vm.assume(!vault.isAllocator(caller) && !vault.isSentinel(caller));
        vm.expectRevert(IBlueAdapterV2PublicAllocator.Unauthorized.selector);
        vm.prank(caller);
        publicAllocator.setAbsoluteCap(address(vault), address(adapter), marketParams2, cap);
    }

    function testSetAbsoluteCapSentinelCanOnlyDecrease(uint256 cap, uint256 lower, uint256 higher) public {
        cap = bound(cap, 1, type(uint256).max - 1);
        lower = bound(lower, 0, cap);
        higher = bound(higher, cap + 1, type(uint256).max);

        // Allocator sets the cap.
        _setAbsoluteCap(marketParams2, cap);

        // Sentinel cannot increase the cap.
        vm.expectRevert(IBlueAdapterV2PublicAllocator.Unauthorized.selector);
        vm.prank(sentinel);
        publicAllocator.setAbsoluteCap(address(vault), address(adapter), marketParams2, higher);

        // Sentinel can decrease the cap (cut public inflows).
        vm.prank(sentinel);
        publicAllocator.setAbsoluteCap(address(vault), address(adapter), marketParams2, lower);
        assertEq(publicAllocator.absoluteCap(address(vault), id2), lower);
    }

    /* SET CAN DEALLOCATE */

    function testSetCanDeallocate(bool value) public {
        vm.expectEmit();
        emit IBlueAdapterV2PublicAllocator.SetCanDeallocate(
            allocator, address(vault), address(adapter), marketParams1, value
        );
        _setCanDeallocate(marketParams1, value);
        assertEq(publicAllocator.canDeallocate(address(vault), id1), value);
    }

    function testSetCanDeallocateUnauthorized(address caller) public {
        vm.assume(!vault.isAllocator(caller) && !vault.isSentinel(caller));
        vm.expectRevert(IBlueAdapterV2PublicAllocator.Unauthorized.selector);
        vm.prank(caller);
        publicAllocator.setCanDeallocate(address(vault), address(adapter), marketParams1, true);
    }

    function testSetCanDeallocateSentinelCanOnlyEnable() public {
        // Sentinel can enable public deallocations to derisk.
        vm.expectEmit();
        emit IBlueAdapterV2PublicAllocator.SetCanDeallocate(
            sentinel, address(vault), address(adapter), marketParams1, true
        );
        vm.prank(sentinel);
        publicAllocator.setCanDeallocate(address(vault), address(adapter), marketParams1, true);
        assertTrue(publicAllocator.canDeallocate(address(vault), id1));

        // Sentinel cannot disable public deallocations.
        vm.expectRevert(IBlueAdapterV2PublicAllocator.Unauthorized.selector);
        vm.prank(sentinel);
        publicAllocator.setCanDeallocate(address(vault), address(adapter), marketParams1, false);
    }

    function testSetCanDeallocateFromIdle(bool value) public {
        vm.expectEmit();
        emit IBlueAdapterV2PublicAllocator.SetCanDeallocateFromIdle(allocator, address(vault), value);
        _setCanDeallocateFromIdle(value);
        assertEq(publicAllocator.canDeallocateFromIdle(address(vault)), value);
    }

    function testSetCanDeallocateFromIdleUnauthorized(address caller) public {
        vm.assume(!vault.isAllocator(caller) && !vault.isSentinel(caller));
        vm.expectRevert(IBlueAdapterV2PublicAllocator.Unauthorized.selector);
        vm.prank(caller);
        publicAllocator.setCanDeallocateFromIdle(address(vault), true);
    }

    function testSetCanDeallocateFromIdleSentinelCanOnlyDisable() public {
        vm.expectRevert(IBlueAdapterV2PublicAllocator.Unauthorized.selector);
        vm.prank(sentinel);
        publicAllocator.setCanDeallocateFromIdle(address(vault), true);

        _setCanDeallocateFromIdle(true);

        vm.expectEmit();
        emit IBlueAdapterV2PublicAllocator.SetCanDeallocateFromIdle(sentinel, address(vault), false);
        vm.prank(sentinel);
        publicAllocator.setCanDeallocateFromIdle(address(vault), false);
        assertFalse(publicAllocator.canDeallocateFromIdle(address(vault)));
    }

    /* REALLOCATE */

    function testReallocateMovesLiquidity(uint256 assets, uint128 amount) public {
        assets = bound(assets, 1, MAX_TEST_ASSETS);
        amount = uint128(bound(amount, 1, assets));

        _seedMarket1(assets);
        _setCanDeallocate(marketParams1, true);
        _setAbsoluteCap(marketParams2, type(uint256).max);

        uint256 alloc1Before = vault.allocation(id1);
        assertEq(vault.allocation(id2), 0);

        vm.expectEmit();
        emit IBlueAdapterV2PublicAllocator.Reallocate(rando, address(vault), id2, id1, amount, 0);
        _reallocate(amount);

        assertEq(vault.allocation(id1), alloc1Before - amount, "market1");
        assertLe(vault.allocation(id2), amount, "market2 rounds down");
        assertGt(vault.allocation(id2), 0, "market2 supplied");
    }

    function testReallocateCannotDeallocate(uint256 assets, uint128 amount) public {
        assets = bound(assets, 1, MAX_TEST_ASSETS);
        amount = uint128(bound(amount, 1, assets));

        _seedMarket1(assets);
        _setAbsoluteCap(marketParams2, type(uint256).max);
        // market1 deallocation not enabled.

        vm.expectRevert(IBlueAdapterV2PublicAllocator.CannotDeallocate.selector);
        _reallocate(amount);
    }

    function testReallocateAbsoluteCapExceeded(uint256 assets, uint128 amount) public {
        assets = bound(assets, 2, MAX_TEST_ASSETS);
        amount = uint128(bound(amount, 2, assets));

        _seedMarket1(assets);
        _setCanDeallocate(marketParams1, true);
        // Absolute cap on market2 is 0: any non-zero resulting allocation must exceed it.
        _setAbsoluteCap(marketParams2, 0);

        vm.expectRevert(IBlueAdapterV2PublicAllocator.AbsoluteCapExceeded.selector);
        _reallocate(amount);
    }

    function testReallocateWithinAbsoluteCap(uint256 assets, uint128 amount) public {
        assets = bound(assets, 1, MAX_TEST_ASSETS);
        amount = uint128(bound(amount, 1, assets));

        _seedMarket1(assets);
        _setCanDeallocate(marketParams1, true);
        // Resulting allocation is at most `amount` (Morpho rounds down), so `amount` is a valid cap upper bound.
        _setAbsoluteCap(marketParams2, amount);

        _reallocate(amount);

        assertLe(vault.allocation(id2), publicAllocator.absoluteCap(address(vault), id2), "within cap");
    }

    function testAllocateFromIdle(uint256 assets, uint128 amount) public {
        assets = bound(assets, 1, MAX_TEST_ASSETS);
        amount = uint128(bound(amount, 1, assets));

        vault.deposit(assets, address(this));
        _setCanDeallocateFromIdle(true);
        _setAbsoluteCap(marketParams2, type(uint256).max);

        vm.expectEmit();
        emit IBlueAdapterV2PublicAllocator.AllocateFromIdle(rando, address(vault), id2, amount, 0);
        vm.prank(rando);
        publicAllocator.allocateFromIdle(address(vault), address(adapter), marketParams2, amount);

        assertEq(underlyingToken.balanceOf(address(vault)), assets - amount, "idle");
        assertLe(vault.allocation(id2), amount, "market2 rounds down");
        assertGt(vault.allocation(id2), 0, "market2 supplied");
    }

    function testAllocateFromIdleCannotDeallocate(uint256 assets, uint128 amount) public {
        assets = bound(assets, 1, MAX_TEST_ASSETS);
        amount = uint128(bound(amount, 1, assets));

        vault.deposit(assets, address(this));
        _setAbsoluteCap(marketParams2, type(uint256).max);

        vm.expectRevert(IBlueAdapterV2PublicAllocator.CannotDeallocate.selector);
        vm.prank(rando);
        publicAllocator.allocateFromIdle(address(vault), address(adapter), marketParams2, amount);
    }

    function testAllocateFromIdleToIdleReverts(uint256 assets, uint128 amount) public {
        assets = bound(assets, 1, MAX_TEST_ASSETS);
        amount = uint128(bound(amount, 1, assets));

        vault.deposit(assets, address(this));
        _setCanDeallocateFromIdle(true);

        // address(0) is not a factory-created Blue adapter, so the top-level check rejects it first.
        vm.expectRevert(IBlueAdapterV2PublicAllocator.NotBlueAdapter.selector);
        vm.prank(rando);
        publicAllocator.allocateFromIdle(address(vault), address(0), marketParams2, amount);
    }

    function testReallocateRespectsVaultCaps(uint256 assets, uint128 amount) public {
        assets = bound(assets, 2, MAX_TEST_ASSETS);
        amount = uint128(bound(amount, 2, assets));

        _seedMarket1(assets);
        _setCanDeallocate(marketParams1, true);
        _setAbsoluteCap(marketParams2, type(uint256).max);

        // Vault absolute cap on market2 tightened below the amount so the vault's own allocate reverts first.
        // decreaseAbsoluteCap is not timelocked; the curator can call it directly.
        vm.prank(curator);
        vault.decreaseAbsoluteCap(expectedIdData2[2], amount - 1);

        vm.expectRevert(ErrorsLib.AbsoluteCapExceeded.selector);
        _reallocate(amount);
    }

    /* NATIVE PENALTY */

    function testSetNativePenalty(uint256 newNativePenalty) public {
        newNativePenalty = bound(newNativePenalty, 0, type(uint120).max);
        vm.expectEmit();
        emit IBlueAdapterV2PublicAllocator.SetNativePenalty(curator, address(vault), newNativePenalty);
        vm.prank(curator);
        publicAllocator.setNativePenalty(address(vault), newNativePenalty);
        assertEq(publicAllocator.nativePenalty(address(vault)), newNativePenalty);
    }

    function testSetNativePenaltyUnauthorized(address caller, uint256 newNativePenalty) public {
        vm.assume(caller != curator);
        vm.expectRevert(IBlueAdapterV2PublicAllocator.Unauthorized.selector);
        vm.prank(caller);
        publicAllocator.setNativePenalty(address(vault), newNativePenalty);
    }

    function testReallocateChargesNativePenalty(uint256 nativePenaltyAmount, uint256 assets, uint128 amount) public {
        nativePenaltyAmount = bound(nativePenaltyAmount, 1, 10 ether);
        assets = bound(assets, 1, MAX_TEST_ASSETS);
        amount = uint128(bound(amount, 1, assets));
        vm.prank(curator);
        publicAllocator.setNativePenalty(address(vault), nativePenaltyAmount);

        _seedMarket1(assets);
        _setCanDeallocate(marketParams1, true);
        _setAbsoluteCap(marketParams2, type(uint256).max);

        uint256 curatorBalanceBefore = curator.balance;

        vm.deal(rando, nativePenaltyAmount);
        vm.prank(rando);
        publicAllocator.reallocate{value: nativePenaltyAmount}(
            address(vault), address(adapter), marketParams1, address(adapter), marketParams2, amount
        );

        assertEq(curator.balance, curatorBalanceBefore);
        assertEq(publicAllocator.accruedNativePenalty(address(vault)), nativePenaltyAmount);
        assertEq(address(publicAllocator).balance, nativePenaltyAmount);
    }

    function testReallocateAccruesNativePenaltyForNonPayableCurator(
        uint256 nativePenaltyAmount,
        uint256 assets,
        uint128 amount
    ) public {
        nativePenaltyAmount = bound(nativePenaltyAmount, 1, 10 ether);
        assets = bound(assets, 1, MAX_TEST_ASSETS);
        amount = uint128(bound(amount, 1, assets));

        address nonPayableCurator = address(new RejectNative());
        vm.prank(owner);
        vault.setCurator(nonPayableCurator);
        vm.prank(nonPayableCurator);
        publicAllocator.setNativePenalty(address(vault), nativePenaltyAmount);

        _seedMarket1(assets);
        // canDeallocate / absoluteCap are allocator-set roles, independent of the curator swap.
        _setCanDeallocate(marketParams1, true);
        _setAbsoluteCap(marketParams2, type(uint256).max);

        vm.deal(rando, nativePenaltyAmount);
        vm.prank(rando);
        publicAllocator.reallocate{value: nativePenaltyAmount}(
            address(vault), address(adapter), marketParams1, address(adapter), marketParams2, amount
        );

        assertEq(nonPayableCurator.balance, 0);
        assertEq(publicAllocator.accruedNativePenalty(address(vault)), nativePenaltyAmount);
        assertEq(address(publicAllocator).balance, nativePenaltyAmount);
    }

    function testClaimNativePenalty(uint256 nativePenaltyAmount, uint256 assets, uint128 amount) public {
        nativePenaltyAmount = bound(nativePenaltyAmount, 1, 10 ether);
        assets = bound(assets, 1, MAX_TEST_ASSETS);
        amount = uint128(bound(amount, 1, assets));
        address payable receiver = payable(makeAddr("receiver"));

        vm.prank(curator);
        publicAllocator.setNativePenalty(address(vault), nativePenaltyAmount);
        _seedMarket1(assets);
        _setCanDeallocate(marketParams1, true);
        _setAbsoluteCap(marketParams2, type(uint256).max);

        vm.deal(rando, nativePenaltyAmount);
        vm.prank(rando);
        publicAllocator.reallocate{value: nativePenaltyAmount}(
            address(vault), address(adapter), marketParams1, address(adapter), marketParams2, amount
        );

        vm.expectEmit();
        emit IBlueAdapterV2PublicAllocator.ClaimNativePenalty(curator, address(vault), nativePenaltyAmount, receiver);
        vm.prank(curator);
        publicAllocator.claimNativePenalty(address(vault), receiver);

        assertEq(publicAllocator.accruedNativePenalty(address(vault)), 0);
        assertEq(receiver.balance, nativePenaltyAmount);
        assertEq(address(publicAllocator).balance, 0);
    }

    function testClaimNativePenaltyRevertsWhenReceiverRejects(
        uint256 nativePenaltyAmount,
        uint256 assets,
        uint128 amount
    ) public {
        nativePenaltyAmount = bound(nativePenaltyAmount, 1, 10 ether);
        assets = bound(assets, 1, MAX_TEST_ASSETS);
        amount = uint128(bound(amount, 1, assets));
        address payable receiver = payable(address(new RejectNative()));

        vm.prank(curator);
        publicAllocator.setNativePenalty(address(vault), nativePenaltyAmount);
        _seedMarket1(assets);
        _setCanDeallocate(marketParams1, true);
        _setAbsoluteCap(marketParams2, type(uint256).max);

        vm.deal(rando, nativePenaltyAmount);
        vm.prank(rando);
        publicAllocator.reallocate{value: nativePenaltyAmount}(
            address(vault), address(adapter), marketParams1, address(adapter), marketParams2, amount
        );

        vm.expectRevert(IBlueAdapterV2PublicAllocator.NativeTransferFailed.selector);
        vm.prank(curator);
        publicAllocator.claimNativePenalty(address(vault), receiver);

        assertEq(publicAllocator.accruedNativePenalty(address(vault)), nativePenaltyAmount);
        assertEq(receiver.balance, 0);
        assertEq(address(publicAllocator).balance, nativePenaltyAmount);
    }

    function testClaimNativePenaltyUnauthorized(address caller, address payable receiver) public {
        vm.assume(caller != curator);

        vm.expectRevert(IBlueAdapterV2PublicAllocator.Unauthorized.selector);
        vm.prank(caller);
        publicAllocator.claimNativePenalty(address(vault), receiver);
    }

    function testReallocateIncorrectNativePenalty(
        uint256 nativePenaltyAmount,
        uint256 sentValue,
        uint256 assets,
        uint128 amount
    ) public {
        nativePenaltyAmount = bound(nativePenaltyAmount, 1, 10 ether);
        sentValue = bound(sentValue, 0, 10 ether);
        vm.assume(sentValue != nativePenaltyAmount);
        assets = bound(assets, 1, MAX_TEST_ASSETS);
        amount = uint128(bound(amount, 1, assets));
        vm.prank(curator);
        publicAllocator.setNativePenalty(address(vault), nativePenaltyAmount);

        _seedMarket1(assets);
        _setCanDeallocate(marketParams1, true);
        _setAbsoluteCap(marketParams2, type(uint256).max);

        vm.deal(rando, sentValue);
        vm.expectRevert(IBlueAdapterV2PublicAllocator.IncorrectNativePenalty.selector);
        vm.prank(rando);
        publicAllocator.reallocate{value: sentValue}(
            address(vault), address(adapter), marketParams1, address(adapter), marketParams2, amount
        );
    }
}
