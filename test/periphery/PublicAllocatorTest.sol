// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Morpho Association
pragma solidity ^0.8.28;

import "../BaseTest.sol";
import {AdapterMock} from "../mocks/AdapterMock.sol";
import {PublicAllocator} from "../../src/periphery/PublicAllocator.sol";
import {IPublicAllocator} from "../../src/periphery/interfaces/IPublicAllocator.sol";

contract RejectEth {}

contract GasHungryEthReceiver {
    uint256 public received;

    receive() external payable {
        received += msg.value;
    }
}

contract PublicAllocatorTest is BaseTest {
    PublicAllocator internal publicAllocator;

    address internal adapterA;
    address internal adapterB;

    bytes internal dataA = hex"a1";
    bytes internal dataB = hex"b2";

    bytes32 internal keyA;
    bytes32 internal keyB;

    address internal rando = makeAddr("rando");

    function setUp() public override {
        super.setUp();

        publicAllocator = new PublicAllocator();

        adapterA = address(new AdapterMock(address(vault)));
        adapterB = address(new AdapterMock(address(vault)));

        keyA = keccak256(abi.encode(adapterA, dataA));
        keyB = keccak256(abi.encode(adapterB, dataB));

        // Add adapters and make the public allocator an allocator (timelocks are 0 at setup).
        vm.startPrank(curator);
        vault.submit(abi.encodeCall(IVaultV2.addAdapter, (adapterA)));
        vault.submit(abi.encodeCall(IVaultV2.addAdapter, (adapterB)));
        vault.submit(abi.encodeCall(IVaultV2.setIsAllocator, (address(publicAllocator), true)));
        vm.stopPrank();
        vault.addAdapter(adapterA);
        vault.addAdapter(adapterB);
        vault.setIsAllocator(address(publicAllocator), true);

        // Caps: AdapterMock returns ids "id-0"/"id-1" shared by both adapters.
        increaseAbsoluteCap("id-0", type(uint128).max);
        increaseAbsoluteCap("id-1", type(uint128).max);
        increaseRelativeCap("id-0", WAD);
        increaseRelativeCap("id-1", WAD);

        deal(address(underlyingToken), address(this), type(uint256).max);
        underlyingToken.approve(address(vault), type(uint256).max);
    }

    /* HELPERS */

    // Flags are set by the vault's allocators (inherited role).
    function _setCanAllocate(address adapter, bytes memory data, bool value) internal {
        vm.prank(allocator);
        publicAllocator.setCanAllocate(address(vault), adapter, data, value);
    }

    function _setCanDeallocate(address adapter, bytes memory data, bool value) internal {
        vm.prank(allocator);
        publicAllocator.setCanDeallocate(address(vault), adapter, data, value);
    }

    function _seedAdapterA(uint256 assets) internal {
        vault.deposit(assets, address(this));
        vm.prank(allocator);
        vault.allocate(adapterA, dataA, assets);
    }

    function _reallocate(uint128 assets) internal {
        vm.prank(rando);
        publicAllocator.reallocate(address(vault), adapterA, dataA, adapterB, dataB, assets);
    }

    function decreaseRelativeCap(bytes memory idData, uint256 relativeCap) internal {
        vm.prank(curator);
        vault.decreaseRelativeCap(idData, relativeCap);
    }

    /* SET CAN ALLOCATE */

    function testSetCanAllocate(bool value) public {
        vm.expectEmit();
        emit IPublicAllocator.SetCanAllocate(allocator, address(vault), adapterA, dataA, value);
        _setCanAllocate(adapterA, dataA, value);
        assertEq(publicAllocator.canAllocate(address(vault), keyA), value);
    }

    function testSetCanAllocateUnauthorized(address caller) public {
        vm.assume(!vault.isAllocator(caller) && !vault.isSentinel(caller));
        vm.expectRevert(IPublicAllocator.Unauthorized.selector);
        vm.prank(caller);
        publicAllocator.setCanAllocate(address(vault), adapterA, dataA, true);
    }

    function testSetCanAllocateSentinelCanOnlyDisable() public {
        // Enable via allocator first.
        _setCanAllocate(adapterA, dataA, true);

        // Sentinel cannot enable.
        vm.expectRevert(IPublicAllocator.Unauthorized.selector);
        vm.prank(sentinel);
        publicAllocator.setCanAllocate(address(vault), adapterA, dataA, true);

        // Sentinel can disable (cut public inflows).
        vm.prank(sentinel);
        publicAllocator.setCanAllocate(address(vault), adapterA, dataA, false);
        assertFalse(publicAllocator.canAllocate(address(vault), keyA));
    }

    /* SET CAN DEALLOCATE */

    function testSetCanDeallocate(bool value) public {
        vm.expectEmit();
        emit IPublicAllocator.SetCanDeallocate(allocator, address(vault), adapterA, dataA, value);
        _setCanDeallocate(adapterA, dataA, value);
        assertEq(publicAllocator.canDeallocate(address(vault), keyA), value);
    }

    function testSetCanDeallocateUnauthorized(address caller) public {
        vm.assume(!vault.isAllocator(caller) && !vault.isSentinel(caller));
        vm.expectRevert(IPublicAllocator.Unauthorized.selector);
        vm.prank(caller);
        publicAllocator.setCanDeallocate(address(vault), adapterA, dataA, true);
    }

    function testSetCanDeallocateSentinelCanOnlyEnable() public {
        // Sentinel can enable public deallocations to derisk.
        vm.expectEmit();
        emit IPublicAllocator.SetCanDeallocate(sentinel, address(vault), adapterA, dataA, true);
        vm.prank(sentinel);
        publicAllocator.setCanDeallocate(address(vault), adapterA, dataA, true);
        assertTrue(publicAllocator.canDeallocate(address(vault), keyA));

        // Sentinel cannot disable public deallocations.
        vm.expectRevert(IPublicAllocator.Unauthorized.selector);
        vm.prank(sentinel);
        publicAllocator.setCanDeallocate(address(vault), adapterA, dataA, false);
    }

    /* REALLOCATE */

    function testReallocateMovesLiquidity(uint256 assets, uint128 amount) public {
        assets = bound(assets, 1, 1e30);
        amount = uint128(bound(amount, 1, assets));

        _seedAdapterA(assets);
        _setCanDeallocate(adapterA, dataA, true);
        _setCanAllocate(adapterB, dataB, true);

        assertEq(AdapterMock(adapterA).deposit(), assets);
        assertEq(AdapterMock(adapterB).deposit(), 0);

        vm.expectEmit();
        emit IPublicAllocator.Reallocate(rando, address(vault), keyB, keyA, amount);
        _reallocate(amount);

        assertEq(AdapterMock(adapterA).deposit(), assets - amount, "adapterA");
        assertEq(AdapterMock(adapterB).deposit(), amount, "adapterB");
    }

    function testReallocateBothWays(uint256 assets, uint128 amount) public {
        assets = bound(assets, 1, 1e30);
        amount = uint128(bound(amount, 1, assets));

        _seedAdapterA(assets);
        // Both adapters can be supplied to and withdrawn from.
        _setCanAllocate(adapterA, dataA, true);
        _setCanAllocate(adapterB, dataB, true);
        _setCanDeallocate(adapterA, dataA, true);
        _setCanDeallocate(adapterB, dataB, true);

        _reallocate(amount);
        assertEq(AdapterMock(adapterA).deposit(), assets - amount);
        assertEq(AdapterMock(adapterB).deposit(), amount);

        // Move it back.
        vm.prank(rando);
        publicAllocator.reallocate(address(vault), adapterB, dataB, adapterA, dataA, amount);
        assertEq(AdapterMock(adapterA).deposit(), assets);
        assertEq(AdapterMock(adapterB).deposit(), 0);
    }

    function testReallocateCannotAllocate(uint256 assets, uint128 amount) public {
        assets = bound(assets, 1, 1e30);
        amount = uint128(bound(amount, 1, assets));

        _seedAdapterA(assets);
        _setCanDeallocate(adapterA, dataA, true);
        // Supply adapter B not enabled.

        vm.expectRevert(IPublicAllocator.CannotAllocate.selector);
        _reallocate(amount);
    }

    function testReallocateCannotDeallocate(uint256 assets, uint128 amount) public {
        assets = bound(assets, 1, 1e30);
        amount = uint128(bound(amount, 1, assets));

        _seedAdapterA(assets);
        _setCanAllocate(adapterB, dataB, true);
        // Withdraw adapter A not enabled.

        vm.expectRevert(IPublicAllocator.CannotDeallocate.selector);
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
        assets = bound(assets, 1, 1e30);
        amount = uint128(bound(amount, 1, assets));
        vm.prank(curator);
        publicAllocator.setEthPenalty(address(vault), ethPenaltyAmount);

        _seedAdapterA(assets);
        _setCanDeallocate(adapterA, dataA, true);
        _setCanAllocate(adapterB, dataB, true);

        uint256 curatorBalanceBefore = curator.balance;

        vm.deal(rando, ethPenaltyAmount);
        vm.prank(rando);
        publicAllocator.reallocate{value: ethPenaltyAmount}(address(vault), adapterA, dataA, adapterB, dataB, amount);

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
        assets = bound(assets, 1, 1e30);
        amount = uint128(bound(amount, 1, assets));

        address nonPayableCurator = address(new RejectEth());
        vm.prank(owner);
        vault.setCurator(nonPayableCurator);
        vm.prank(nonPayableCurator);
        publicAllocator.setEthPenalty(address(vault), ethPenaltyAmount);

        _seedAdapterA(assets);
        _setCanDeallocate(adapterA, dataA, true);
        _setCanAllocate(adapterB, dataB, true);

        vm.deal(rando, ethPenaltyAmount);
        vm.prank(rando);
        publicAllocator.reallocate{value: ethPenaltyAmount}(address(vault), adapterA, dataA, adapterB, dataB, amount);

        assertEq(nonPayableCurator.balance, 0);
        assertEq(publicAllocator.accruedEthPenalty(address(vault)), ethPenaltyAmount);
        assertEq(address(publicAllocator).balance, ethPenaltyAmount);
        assertEq(AdapterMock(adapterA).deposit(), assets - amount, "adapterA");
        assertEq(AdapterMock(adapterB).deposit(), amount, "adapterB");
    }

    function testClaimEthPenalty(uint256 ethPenaltyAmount, uint256 assets, uint128 amount) public {
        ethPenaltyAmount = bound(ethPenaltyAmount, 1, 10 ether);
        assets = bound(assets, 1, 1e30);
        amount = uint128(bound(amount, 1, assets));
        address payable receiver = payable(makeAddr("receiver"));

        vm.prank(curator);
        publicAllocator.setEthPenalty(address(vault), ethPenaltyAmount);
        _seedAdapterA(assets);
        _setCanDeallocate(adapterA, dataA, true);
        _setCanAllocate(adapterB, dataB, true);

        vm.deal(rando, ethPenaltyAmount);
        vm.prank(rando);
        publicAllocator.reallocate{value: ethPenaltyAmount}(address(vault), adapterA, dataA, adapterB, dataB, amount);

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
        assets = bound(assets, 1, 1e30);
        amount = uint128(bound(amount, 1, assets));
        GasHungryEthReceiver receiver = new GasHungryEthReceiver();

        vm.prank(curator);
        publicAllocator.setEthPenalty(address(vault), ethPenaltyAmount);
        _seedAdapterA(assets);
        _setCanDeallocate(adapterA, dataA, true);
        _setCanAllocate(adapterB, dataB, true);

        vm.deal(rando, ethPenaltyAmount);
        vm.prank(rando);
        publicAllocator.reallocate{value: ethPenaltyAmount}(address(vault), adapterA, dataA, adapterB, dataB, amount);

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
        assets = bound(assets, 1, 1e30);
        amount = uint128(bound(amount, 1, assets));
        address payable receiver = payable(address(new RejectEth()));

        vm.prank(curator);
        publicAllocator.setEthPenalty(address(vault), ethPenaltyAmount);
        _seedAdapterA(assets);
        _setCanDeallocate(adapterA, dataA, true);
        _setCanAllocate(adapterB, dataB, true);

        vm.deal(rando, ethPenaltyAmount);
        vm.prank(rando);
        publicAllocator.reallocate{value: ethPenaltyAmount}(address(vault), adapterA, dataA, adapterB, dataB, amount);

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
        assets = bound(assets, 1, 1e30);
        amount = uint128(bound(amount, 1, assets));
        vm.prank(curator);
        publicAllocator.setEthPenalty(address(vault), ethPenaltyAmount);

        _seedAdapterA(assets);
        _setCanAllocate(adapterB, dataB, true);

        vm.deal(rando, sentValue);
        vm.expectRevert(IPublicAllocator.IncorrectEthPenalty.selector);
        vm.prank(rando);
        publicAllocator.reallocate{value: sentValue}(address(vault), adapterA, dataA, adapterB, dataB, amount);
    }

    function testReallocateRespectsVaultCaps(uint256 assets, uint128 amount) public {
        assets = bound(assets, 1, 1e30);
        amount = uint128(bound(amount, 1, assets));

        _seedAdapterA(assets);
        _setCanDeallocate(adapterA, dataA, true);
        _setCanAllocate(adapterB, dataB, true);

        // Vault relative cap on a shared id tightened so the supply allocation would exceed it.
        decreaseRelativeCap("id-0", 0);

        vm.expectRevert(ErrorsLib.RelativeCapExceeded.selector);
        _reallocate(amount);
    }
}
