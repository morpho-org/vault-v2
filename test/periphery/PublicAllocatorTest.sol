// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Morpho Association
pragma solidity ^0.8.28;

import "../BaseTest.sol";
import {AdapterMock} from "../mocks/AdapterMock.sol";
import {PublicAllocator} from "../../src/periphery/PublicAllocator.sol";
import {IPublicAllocator} from "../../src/periphery/interfaces/IPublicAllocator.sol";

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

    function _seedAdapterA(uint256 assets) internal {
        vault.deposit(assets, address(this));
        vm.prank(allocator);
        vault.allocate(adapterA, dataA, assets);
    }

    function _reallocate(uint128 amount) internal {
        vm.prank(rando);
        publicAllocator.reallocate(address(vault), adapterA, dataA, adapterB, dataB, amount);
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

    /* REALLOCATE */

    function testReallocateMovesLiquidity(uint256 assets, uint128 amount) public {
        assets = bound(assets, 1, 1e30);
        amount = uint128(bound(amount, 1, assets));

        _seedAdapterA(assets);
        _setCanAllocate(adapterB, dataB, true); // can supply to B; withdrawing from A is unrestricted

        assertEq(AdapterMock(adapterA).deposit(), assets);
        assertEq(AdapterMock(adapterB).deposit(), 0);

        vm.expectEmit();
        emit IPublicAllocator.Reallocate(rando, address(vault), keyB, keyA, amount);
        _reallocate(amount);

        assertEq(AdapterMock(adapterA).deposit(), assets - amount, "adapterA");
        assertEq(AdapterMock(adapterB).deposit(), amount, "adapterB");
    }

    function testReallocateBothWays() public {
        uint256 assets = 10e18;
        _seedAdapterA(assets);
        // Both adapters can be supplied to; withdrawing from either is unrestricted.
        _setCanAllocate(adapterA, dataA, true);
        _setCanAllocate(adapterB, dataB, true);

        _reallocate(3e18);
        assertEq(AdapterMock(adapterA).deposit(), 7e18);
        assertEq(AdapterMock(adapterB).deposit(), 3e18);

        // Move it back.
        vm.prank(rando);
        publicAllocator.reallocate(address(vault), adapterB, dataB, adapterA, dataA, 3e18);
        assertEq(AdapterMock(adapterA).deposit(), assets);
        assertEq(AdapterMock(adapterB).deposit(), 0);
    }

    function testReallocateCannotAllocate() public {
        _seedAdapterA(10e18);
        // Supply adapter B not enabled.

        vm.expectRevert(IPublicAllocator.CannotAllocate.selector);
        _reallocate(1e18);
    }

    /* FEE */

    function testSetFee(uint256 newFee) public {
        vm.expectEmit();
        emit IPublicAllocator.SetFee(allocator, address(vault), newFee);
        vm.prank(allocator);
        publicAllocator.setFee(address(vault), newFee);
        assertEq(publicAllocator.fee(address(vault)), newFee);
    }

    function testSetFeeUnauthorized(address caller, uint256 newFee) public {
        vm.assume(!vault.isAllocator(caller));
        vm.expectRevert(IPublicAllocator.Unauthorized.selector);
        vm.prank(caller);
        publicAllocator.setFee(address(vault), newFee);
    }

    function testReallocateChargesFee(uint256 feeAmount) public {
        feeAmount = bound(feeAmount, 1, 10 ether);
        vm.prank(allocator);
        publicAllocator.setFee(address(vault), feeAmount);

        _seedAdapterA(1e18);
        _setCanAllocate(adapterB, dataB, true);

        vm.deal(rando, feeAmount);
        vm.prank(rando);
        publicAllocator.reallocate{value: feeAmount}(address(vault), adapterA, dataA, adapterB, dataB, 1e18);

        assertEq(publicAllocator.accruedFee(address(vault)), feeAmount);
        assertEq(address(publicAllocator).balance, feeAmount);
    }

    function testReallocateIncorrectFee(uint256 feeAmount, uint256 sentValue) public {
        feeAmount = bound(feeAmount, 1, 10 ether);
        sentValue = bound(sentValue, 0, 10 ether);
        vm.assume(sentValue != feeAmount);
        vm.prank(allocator);
        publicAllocator.setFee(address(vault), feeAmount);

        _seedAdapterA(1e18);
        _setCanAllocate(adapterB, dataB, true);

        vm.deal(rando, sentValue);
        vm.expectRevert(IPublicAllocator.IncorrectFee.selector);
        vm.prank(rando);
        publicAllocator.reallocate{value: sentValue}(address(vault), adapterA, dataA, adapterB, dataB, 1e18);
    }

    function testClaimFee(uint256 feeAmount) public {
        feeAmount = bound(feeAmount, 1, 10 ether);
        vm.prank(allocator);
        publicAllocator.setFee(address(vault), feeAmount);

        _seedAdapterA(1e18);
        _setCanAllocate(adapterB, dataB, true);
        vm.deal(rando, feeAmount);
        vm.prank(rando);
        publicAllocator.reallocate{value: feeAmount}(address(vault), adapterA, dataA, adapterB, dataB, 1e18);

        address payable recipient = payable(makeAddr("recipient"));
        vm.expectEmit();
        emit IPublicAllocator.ClaimFee(allocator, address(vault), feeAmount, recipient);
        vm.prank(allocator);
        publicAllocator.claimFee(address(vault), recipient);

        assertEq(recipient.balance, feeAmount);
        assertEq(publicAllocator.accruedFee(address(vault)), 0);
        assertEq(address(publicAllocator).balance, 0);
    }

    function testClaimFeeUnauthorized(address caller) public {
        vm.assume(!vault.isAllocator(caller));
        vm.expectRevert(IPublicAllocator.Unauthorized.selector);
        vm.prank(caller);
        publicAllocator.claimFee(address(vault), payable(caller));
    }

    function testReallocateRespectsVaultCaps() public {
        _seedAdapterA(10e18);
        _setCanAllocate(adapterB, dataB, true);

        // Vault relative cap on a shared id tightened so the supply allocation would exceed it.
        decreaseRelativeCap("id-0", 0);

        vm.expectRevert(ErrorsLib.RelativeCapExceeded.selector);
        _reallocate(5e18);
    }
}
