// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Morpho Association
pragma solidity ^0.8.28;

import "../integration/MorphoMarketV1IntegrationTest.sol";

import {PublicAllocator} from "../../src/periphery/PublicAllocator.sol";
import {IPublicAllocator} from "../../src/periphery/interfaces/IPublicAllocator.sol";

contract RejectEth {}

contract GasHungryEthReceiver {
    uint256 public received;

    receive() external payable {
        received += msg.value;
    }
}

/// @dev The public allocator is specialized to Morpho Market V1 (Morpho Blue) via the Morpho Market V1 adapter (V2).
/// These tests use a real vault + adapter + Morpho Blue markets so that the absolute cap is keyed by the exact
/// per-market vault id (keccak256(abi.encode("this/marketParams", adapter, marketParams))).
contract PublicAllocatorTest is MorphoMarketV1IntegrationTest {
    using MorphoBalancesLib for IMorpho;

    PublicAllocator internal publicAllocator;

    address internal rando = makeAddr("rando");

    // Per-market vault ids (== expectedIds1[2] / expectedIds2[2] from the integration harness).
    bytes32 internal id1;
    bytes32 internal id2;

    function setUp() public override {
        super.setUp();

        id1 = expectedIds1[2];
        id2 = expectedIds2[2];

        publicAllocator = new PublicAllocator();

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
        emit IPublicAllocator.SetAbsoluteCap(allocator, address(vault), address(adapter), marketParams2, cap);
        _setAbsoluteCap(marketParams2, cap);
        assertEq(publicAllocator.absoluteCap(address(vault), id2), cap);
    }

    function testSetAbsoluteCapUnauthorized(address caller, uint256 cap) public {
        vm.assume(!vault.isAllocator(caller) && !vault.isSentinel(caller));
        vm.expectRevert(IPublicAllocator.Unauthorized.selector);
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
        vm.expectRevert(IPublicAllocator.Unauthorized.selector);
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
        emit IPublicAllocator.SetCanDeallocate(allocator, address(vault), address(adapter), marketParams1, value);
        _setCanDeallocate(marketParams1, value);
        assertEq(publicAllocator.canDeallocate(address(vault), id1), value);
    }

    function testSetCanDeallocateUnauthorized(address caller) public {
        vm.assume(!vault.isAllocator(caller) && !vault.isSentinel(caller));
        vm.expectRevert(IPublicAllocator.Unauthorized.selector);
        vm.prank(caller);
        publicAllocator.setCanDeallocate(address(vault), address(adapter), marketParams1, true);
    }

    function testSetCanDeallocateSentinelCanOnlyEnable() public {
        // Sentinel can enable public deallocations to derisk.
        vm.expectEmit();
        emit IPublicAllocator.SetCanDeallocate(sentinel, address(vault), address(adapter), marketParams1, true);
        vm.prank(sentinel);
        publicAllocator.setCanDeallocate(address(vault), address(adapter), marketParams1, true);
        assertTrue(publicAllocator.canDeallocate(address(vault), id1));

        // Sentinel cannot disable public deallocations.
        vm.expectRevert(IPublicAllocator.Unauthorized.selector);
        vm.prank(sentinel);
        publicAllocator.setCanDeallocate(address(vault), address(adapter), marketParams1, false);
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
        emit IPublicAllocator.Reallocate(rando, address(vault), id2, id1, amount);
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

        vm.expectRevert(IPublicAllocator.CannotDeallocate.selector);
        _reallocate(amount);
    }

    function testReallocateAbsoluteCapExceeded(uint256 assets, uint128 amount) public {
        assets = bound(assets, 2, MAX_TEST_ASSETS);
        amount = uint128(bound(amount, 2, assets));

        _seedMarket1(assets);
        _setCanDeallocate(marketParams1, true);
        // Absolute cap on market2 is 0: any non-zero resulting allocation must exceed it.
        _setAbsoluteCap(marketParams2, 0);

        vm.expectRevert(IPublicAllocator.AbsoluteCapExceeded.selector);
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

    function testReallocateFromIdle(uint256 assets, uint128 amount) public {
        assets = bound(assets, 1, MAX_TEST_ASSETS);
        amount = uint128(bound(amount, 1, assets));

        vault.deposit(assets, address(this));
        _setAbsoluteCap(marketParams2, type(uint256).max);

        vm.expectEmit();
        emit IPublicAllocator.Reallocate(rando, address(vault), id2, publicAllocator.IDLE_ID(), amount);
        vm.prank(rando);
        publicAllocator.reallocate(address(vault), address(0), marketParams1, address(adapter), marketParams2, amount);

        assertEq(underlyingToken.balanceOf(address(vault)), assets - amount, "idle");
        assertLe(vault.allocation(id2), amount, "market2 rounds down");
        assertGt(vault.allocation(id2), 0, "market2 supplied");
    }

    function testReallocateToIdleReverts(uint256 assets, uint128 amount) public {
        assets = bound(assets, 1, MAX_TEST_ASSETS);
        amount = uint128(bound(amount, 1, assets));

        vault.deposit(assets, address(this));

        vm.expectRevert(ErrorsLib.NotAdapter.selector);
        vm.prank(rando);
        publicAllocator.reallocate(address(vault), address(0), marketParams1, address(0), marketParams2, amount);
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

    /* ETH PENALTY */

    function testSetEthPenalty(uint256 newEthPenalty) public {
        vm.expectEmit();
        emit IPublicAllocator.SetEthPenalty(curator, address(vault), newEthPenalty);
        vm.prank(curator);
        publicAllocator.setEthPenalty(address(vault), newEthPenalty);
        assertEq(publicAllocator.ethPenalty(address(vault)), newEthPenalty);
    }

    function testSetEthPenaltyUnauthorized(address caller, uint256 newEthPenalty) public {
        vm.assume(caller != curator);
        vm.expectRevert(IPublicAllocator.Unauthorized.selector);
        vm.prank(caller);
        publicAllocator.setEthPenalty(address(vault), newEthPenalty);
    }

    function testReallocateChargesEthPenalty(uint256 ethPenaltyAmount, uint256 assets, uint128 amount) public {
        ethPenaltyAmount = bound(ethPenaltyAmount, 1, 10 ether);
        assets = bound(assets, 1, MAX_TEST_ASSETS);
        amount = uint128(bound(amount, 1, assets));
        vm.prank(curator);
        publicAllocator.setEthPenalty(address(vault), ethPenaltyAmount);

        _seedMarket1(assets);
        _setCanDeallocate(marketParams1, true);
        _setAbsoluteCap(marketParams2, type(uint256).max);

        uint256 curatorBalanceBefore = curator.balance;

        vm.deal(rando, ethPenaltyAmount);
        vm.prank(rando);
        publicAllocator.reallocate{value: ethPenaltyAmount}(
            address(vault), address(adapter), marketParams1, address(adapter), marketParams2, amount
        );

        assertEq(curator.balance, curatorBalanceBefore);
        assertEq(publicAllocator.accruedEthPenalty(address(vault)), ethPenaltyAmount);
        assertEq(address(publicAllocator).balance, ethPenaltyAmount);
    }

    function testReallocateAccruesEthPenaltyForNonPayableCurator(
        uint256 ethPenaltyAmount,
        uint256 assets,
        uint128 amount
    ) public {
        ethPenaltyAmount = bound(ethPenaltyAmount, 1, 10 ether);
        assets = bound(assets, 1, MAX_TEST_ASSETS);
        amount = uint128(bound(amount, 1, assets));

        address nonPayableCurator = address(new RejectEth());
        vm.prank(owner);
        vault.setCurator(nonPayableCurator);
        vm.prank(nonPayableCurator);
        publicAllocator.setEthPenalty(address(vault), ethPenaltyAmount);

        _seedMarket1(assets);
        // canDeallocate / absoluteCap are allocator-set roles, independent of the curator swap.
        _setCanDeallocate(marketParams1, true);
        _setAbsoluteCap(marketParams2, type(uint256).max);

        vm.deal(rando, ethPenaltyAmount);
        vm.prank(rando);
        publicAllocator.reallocate{value: ethPenaltyAmount}(
            address(vault), address(adapter), marketParams1, address(adapter), marketParams2, amount
        );

        assertEq(nonPayableCurator.balance, 0);
        assertEq(publicAllocator.accruedEthPenalty(address(vault)), ethPenaltyAmount);
        assertEq(address(publicAllocator).balance, ethPenaltyAmount);
    }

    function testClaimEthPenalty(uint256 ethPenaltyAmount, uint256 assets, uint128 amount) public {
        ethPenaltyAmount = bound(ethPenaltyAmount, 1, 10 ether);
        assets = bound(assets, 1, MAX_TEST_ASSETS);
        amount = uint128(bound(amount, 1, assets));
        address payable receiver = payable(makeAddr("receiver"));

        vm.prank(curator);
        publicAllocator.setEthPenalty(address(vault), ethPenaltyAmount);
        _seedMarket1(assets);
        _setCanDeallocate(marketParams1, true);
        _setAbsoluteCap(marketParams2, type(uint256).max);

        vm.deal(rando, ethPenaltyAmount);
        vm.prank(rando);
        publicAllocator.reallocate{value: ethPenaltyAmount}(
            address(vault), address(adapter), marketParams1, address(adapter), marketParams2, amount
        );

        vm.expectEmit();
        emit IPublicAllocator.ClaimEthPenalty(curator, address(vault), ethPenaltyAmount, receiver);
        vm.prank(curator);
        publicAllocator.claimEthPenalty(address(vault), receiver);

        assertEq(publicAllocator.accruedEthPenalty(address(vault)), 0);
        assertEq(receiver.balance, ethPenaltyAmount);
        assertEq(address(publicAllocator).balance, 0);
    }

    function testClaimEthPenaltyForGasHungryReceiver(uint256 ethPenaltyAmount, uint256 assets, uint128 amount) public {
        ethPenaltyAmount = bound(ethPenaltyAmount, 1, 10 ether);
        assets = bound(assets, 1, MAX_TEST_ASSETS);
        amount = uint128(bound(amount, 1, assets));
        GasHungryEthReceiver receiver = new GasHungryEthReceiver();

        vm.prank(curator);
        publicAllocator.setEthPenalty(address(vault), ethPenaltyAmount);
        _seedMarket1(assets);
        _setCanDeallocate(marketParams1, true);
        _setAbsoluteCap(marketParams2, type(uint256).max);

        vm.deal(rando, ethPenaltyAmount);
        vm.prank(rando);
        publicAllocator.reallocate{value: ethPenaltyAmount}(
            address(vault), address(adapter), marketParams1, address(adapter), marketParams2, amount
        );

        vm.expectEmit();
        emit IPublicAllocator.ClaimEthPenalty(curator, address(vault), ethPenaltyAmount, address(receiver));
        vm.prank(curator);
        publicAllocator.claimEthPenalty(address(vault), payable(address(receiver)));

        assertEq(publicAllocator.accruedEthPenalty(address(vault)), 0);
        assertEq(address(receiver).balance, ethPenaltyAmount);
        assertEq(receiver.received(), ethPenaltyAmount);
        assertEq(address(publicAllocator).balance, 0);
    }

    function testClaimEthPenaltyRevertsWhenReceiverRejects(uint256 ethPenaltyAmount, uint256 assets, uint128 amount)
        public
    {
        ethPenaltyAmount = bound(ethPenaltyAmount, 1, 10 ether);
        assets = bound(assets, 1, MAX_TEST_ASSETS);
        amount = uint128(bound(amount, 1, assets));
        address payable receiver = payable(address(new RejectEth()));

        vm.prank(curator);
        publicAllocator.setEthPenalty(address(vault), ethPenaltyAmount);
        _seedMarket1(assets);
        _setCanDeallocate(marketParams1, true);
        _setAbsoluteCap(marketParams2, type(uint256).max);

        vm.deal(rando, ethPenaltyAmount);
        vm.prank(rando);
        publicAllocator.reallocate{value: ethPenaltyAmount}(
            address(vault), address(adapter), marketParams1, address(adapter), marketParams2, amount
        );

        vm.expectRevert(IPublicAllocator.EthTransferFailed.selector);
        vm.prank(curator);
        publicAllocator.claimEthPenalty(address(vault), receiver);

        assertEq(publicAllocator.accruedEthPenalty(address(vault)), ethPenaltyAmount);
        assertEq(receiver.balance, 0);
        assertEq(address(publicAllocator).balance, ethPenaltyAmount);
    }

    function testClaimEthPenaltyUnauthorized(address caller, address payable receiver) public {
        vm.assume(caller != curator);

        vm.expectRevert(IPublicAllocator.Unauthorized.selector);
        vm.prank(caller);
        publicAllocator.claimEthPenalty(address(vault), receiver);
    }

    function testReallocateIncorrectEthPenalty(
        uint256 ethPenaltyAmount,
        uint256 sentValue,
        uint256 assets,
        uint128 amount
    ) public {
        ethPenaltyAmount = bound(ethPenaltyAmount, 1, 10 ether);
        sentValue = bound(sentValue, 0, 10 ether);
        vm.assume(sentValue != ethPenaltyAmount);
        assets = bound(assets, 1, MAX_TEST_ASSETS);
        amount = uint128(bound(amount, 1, assets));
        vm.prank(curator);
        publicAllocator.setEthPenalty(address(vault), ethPenaltyAmount);

        _seedMarket1(assets);
        _setCanDeallocate(marketParams1, true);
        _setAbsoluteCap(marketParams2, type(uint256).max);

        vm.deal(rando, sentValue);
        vm.expectRevert(IPublicAllocator.IncorrectEthPenalty.selector);
        vm.prank(rando);
        publicAllocator.reallocate{value: sentValue}(
            address(vault), address(adapter), marketParams1, address(adapter), marketParams2, amount
        );
    }
}
