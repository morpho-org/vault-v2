// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Morpho Association
pragma solidity ^0.8.28;

import "../integration/MorphoMarketV1IntegrationTest.sol";

import {BluePublicAllocator} from "../../src/periphery/blue-public-allocator/BluePublicAllocator.sol";
import {IBluePublicAllocator} from "../../src/periphery/blue-public-allocator/interfaces/IBluePublicAllocator.sol";
import {MorphoMarketV1AdapterV2} from "../../src/adapters/MorphoMarketV1AdapterV2.sol";

/// @dev The public allocator is specialized to Morpho Market V1 (Morpho Blue) via the Morpho Market V1 adapter (V2).
/// These tests use a real vault + adapter + Morpho Blue markets so that the absolute cap is keyed by the exact
/// per-market vault id (keccak256(abi.encode("this/marketParams", adapter, marketParams))).
contract BluePublicAllocatorTest is MorphoMarketV1IntegrationTest {
    using MorphoBalancesLib for IMorpho;

    BluePublicAllocator internal bluePublicAllocator;
    IMorphoMarketV1AdapterV2 internal secondAdapter;

    address internal rando = makeAddr("rando");

    // Per-market vault ids (== expectedIds1[2] / expectedIds2[2] from the integration harness).
    bytes32 internal id1;
    bytes32 internal id2;
    bytes32 internal secondAdapterId1;
    bytes32 internal secondAdapterId2;

    function setUp() public override {
        super.setUp();

        id1 = expectedIds1[2];
        id2 = expectedIds2[2];

        secondAdapter = IMorphoMarketV1AdapterV2(
            address(new MorphoMarketV1AdapterV2(address(vault), address(morpho), address(irm)))
        );

        bluePublicAllocator = new BluePublicAllocator(address(vaultFactory));

        bytes memory secondAdapterIdData = abi.encode("this", address(secondAdapter));
        bytes memory secondAdapterIdData1 = abi.encode("this/marketParams", address(secondAdapter), marketParams1);
        bytes memory secondAdapterIdData2 = abi.encode("this/marketParams", address(secondAdapter), marketParams2);
        secondAdapterId1 = keccak256(secondAdapterIdData1);
        secondAdapterId2 = keccak256(secondAdapterIdData2);

        vm.prank(curator);
        vault.submit(abi.encodeCall(IVaultV2.addAdapter, (address(secondAdapter))));
        vault.addAdapter(address(secondAdapter));

        increaseAbsoluteCap(secondAdapterIdData, type(uint128).max);
        increaseRelativeCap(secondAdapterIdData, WAD);
        increaseAbsoluteCap(secondAdapterIdData1, type(uint128).max);
        increaseRelativeCap(secondAdapterIdData1, WAD);
        increaseAbsoluteCap(secondAdapterIdData2, type(uint128).max);
        increaseRelativeCap(secondAdapterIdData2, WAD);

        // Make the public allocator an allocator of the vault (timelocks are 0 at setup).
        vm.prank(curator);
        vault.submit(abi.encodeCall(IVaultV2.setIsAllocator, (address(bluePublicAllocator), true)));
        vault.setIsAllocator(address(bluePublicAllocator), true);
    }

    /* HELPERS */

    function _setIsActiveAdapter(address adapter_, bool value) internal {
        vm.prank(allocator);
        bluePublicAllocator.setIsActiveAdapter(address(vault), adapter_, value);
    }

    // The absolute cap is set by the vault's allocators (inherited role).
    function _setAbsoluteCap(MarketParams memory marketParams, uint256 cap) internal {
        _setAbsoluteCap(address(adapter), marketParams, cap);
    }

    function _setAbsoluteCap(address adapter_, MarketParams memory marketParams, uint256 cap) internal {
        vm.prank(allocator);
        bluePublicAllocator.setAbsoluteCap(address(vault), adapter_, marketParams, cap);
    }

    function _setCanPullFromMarket(MarketParams memory marketParams, bool value) internal {
        _setCanPullFromMarket(address(adapter), marketParams, value);
    }

    function _setCanPullFromMarket(address adapter_, MarketParams memory marketParams, bool value) internal {
        vm.prank(allocator);
        bluePublicAllocator.setCanPullFromMarket(address(vault), adapter_, marketParams, value);
    }

    function _setCanPullFromIdle(bool value) internal {
        vm.prank(allocator);
        bluePublicAllocator.setCanPullFromIdle(address(vault), value);
    }

    // Deposit into the vault and allocate to market1 so there is liquidity to reallocate away from.
    function _seedMarket1(uint256 assets) internal {
        vault.deposit(assets, address(this));
        vm.prank(allocator);
        vault.allocate(address(adapter), abi.encode(marketParams1), assets);
    }

    function _currentPenalty() internal view returns (uint64) {
        (, uint64 penalty_) = bluePublicAllocator.vaultData(address(vault));
        return penalty_;
    }

    function _reallocate(uint128 assets) internal {
        uint64 penalty_ = _currentPenalty();
        vm.prank(rando);
        bluePublicAllocator.reallocate(
            address(vault), address(adapter), marketParams1, address(adapter), marketParams2, assets, penalty_
        );
    }

    function _reallocateAcrossAdapters(uint128 assets) internal {
        uint64 penalty_ = _currentPenalty();
        vm.prank(rando);
        bluePublicAllocator.reallocate(
            address(vault), address(adapter), marketParams1, address(secondAdapter), marketParams2, assets, penalty_
        );
    }

    /* VAULT V2 FACTORY CHECK */

    function testVaultV2Factory() public view {
        assertEq(bluePublicAllocator.vaultV2Factory(), address(vaultFactory));
    }

    function testSetIsActiveAdapterNotVaultV2(address notVault) public {
        vm.assume(!vaultFactory.isVaultV2(notVault));
        vm.expectRevert(IBluePublicAllocator.NotVaultV2.selector);
        vm.prank(allocator);
        bluePublicAllocator.setIsActiveAdapter(notVault, address(adapter), true);
    }

    function testSetAbsoluteCapNotVaultV2(address notVault, uint256 cap) public {
        vm.assume(!vaultFactory.isVaultV2(notVault));
        vm.expectRevert(IBluePublicAllocator.NotVaultV2.selector);
        vm.prank(allocator);
        bluePublicAllocator.setAbsoluteCap(notVault, address(adapter), marketParams2, cap);
    }

    function testSetCanPullFromMarketNotVaultV2(address notVault) public {
        vm.assume(!vaultFactory.isVaultV2(notVault));
        vm.expectRevert(IBluePublicAllocator.NotVaultV2.selector);
        vm.prank(allocator);
        bluePublicAllocator.setCanPullFromMarket(notVault, address(adapter), marketParams1, true);
    }

    function testSetCanPullFromIdleNotVaultV2(address notVault) public {
        vm.assume(!vaultFactory.isVaultV2(notVault));
        vm.expectRevert(IBluePublicAllocator.NotVaultV2.selector);
        vm.prank(allocator);
        bluePublicAllocator.setCanPullFromIdle(notVault, true);
    }

    function testSetPenaltyNotVaultV2(address notVault, uint64 newPenalty) public {
        vm.assume(!vaultFactory.isVaultV2(notVault));
        vm.expectRevert(IBluePublicAllocator.NotVaultV2.selector);
        vm.prank(allocator);
        bluePublicAllocator.setPenalty(notVault, newPenalty);
    }

    /* MULTICALL */

    function testMulticall(bool isActiveAdapter_, uint256 cap, bool canPullFromMarket_, bool canPullFromIdle_) public {
        bytes[] memory data = new bytes[](4);
        data[0] = abi.encodeCall(
            IBluePublicAllocator.setIsActiveAdapter, (address(vault), address(adapter), isActiveAdapter_)
        );
        data[1] =
            abi.encodeCall(IBluePublicAllocator.setAbsoluteCap, (address(vault), address(adapter), marketParams2, cap));
        data[2] = abi.encodeCall(
            IBluePublicAllocator.setCanPullFromMarket,
            (address(vault), address(adapter), marketParams1, canPullFromMarket_)
        );
        data[3] = abi.encodeCall(IBluePublicAllocator.setCanPullFromIdle, (address(vault), canPullFromIdle_));

        vm.prank(allocator);
        bluePublicAllocator.multicall(data);

        assertEq(bluePublicAllocator.isActiveAdapter(address(vault), address(adapter)), isActiveAdapter_);
        assertEq(bluePublicAllocator.absoluteCap(address(vault), id2), cap);
        assertEq(bluePublicAllocator.canPullFromMarket(address(vault), id1), canPullFromMarket_);
        (bool canPullFromIdleActual,) = bluePublicAllocator.vaultData(address(vault));
        assertEq(canPullFromIdleActual, canPullFromIdle_);
    }

    function testMulticallBubblesRevert(address caller, bool isActiveAdapter_) public {
        vm.assume(!vault.isAllocator(caller));

        bytes[] memory data = new bytes[](1);
        data[0] = abi.encodeCall(
            IBluePublicAllocator.setIsActiveAdapter, (address(vault), address(adapter), isActiveAdapter_)
        );

        vm.expectRevert(IBluePublicAllocator.Unauthorized.selector);
        vm.prank(caller);
        bluePublicAllocator.multicall(data);
    }

    function testMulticallEmpty() public {
        vm.prank(allocator);
        bluePublicAllocator.multicall(new bytes[](0));
    }

    /* SET ABSOLUTE CAP */

    function testSetAbsoluteCap(uint256 cap) public {
        vm.expectEmit();
        emit IBluePublicAllocator.SetAbsoluteCap(allocator, address(vault), address(adapter), marketParams2, cap);
        _setAbsoluteCap(marketParams2, cap);
        assertEq(bluePublicAllocator.absoluteCap(address(vault), id2), cap);
    }

    function testSetAbsoluteCapUnauthorized(address caller, uint256 cap) public {
        vm.assume(!vault.isAllocator(caller));
        vm.expectRevert(IBluePublicAllocator.Unauthorized.selector);
        vm.prank(caller);
        bluePublicAllocator.setAbsoluteCap(address(vault), address(adapter), marketParams2, cap);
    }

    /* SET CAN DEALLOCATE */

    function testSetCanDeallocate(bool value) public {
        vm.expectEmit();
        emit IBluePublicAllocator.SetCanPullFromMarket(
            allocator, address(vault), address(adapter), marketParams1, value
        );
        _setCanPullFromMarket(marketParams1, value);
        assertEq(bluePublicAllocator.canPullFromMarket(address(vault), id1), value);
    }

    function testSetCanDeallocateUnauthorized(address caller) public {
        vm.assume(!vault.isAllocator(caller));
        vm.expectRevert(IBluePublicAllocator.Unauthorized.selector);
        vm.prank(caller);
        bluePublicAllocator.setCanPullFromMarket(address(vault), address(adapter), marketParams1, true);
    }

    function testSetCanAllocateFromIdle(bool value) public {
        vm.expectEmit();
        emit IBluePublicAllocator.SetCanPullFromIdle(allocator, address(vault), value);
        _setCanPullFromIdle(value);
        (bool canPullFromIdle_,) = bluePublicAllocator.vaultData(address(vault));
        assertEq(canPullFromIdle_, value);
    }

    function testSetCanAllocateFromIdleUnauthorized(address caller) public {
        vm.assume(!vault.isAllocator(caller));
        vm.expectRevert(IBluePublicAllocator.Unauthorized.selector);
        vm.prank(caller);
        bluePublicAllocator.setCanPullFromIdle(address(vault), true);
    }

    /* SET ACTIVE ADAPTER */

    function testSetIsActiveAdapter(bool value) public {
        vm.expectEmit();
        emit IBluePublicAllocator.SetIsActiveAdapter(allocator, address(vault), address(adapter), value);
        _setIsActiveAdapter(address(adapter), value);
        assertEq(bluePublicAllocator.isActiveAdapter(address(vault), address(adapter)), value);
    }

    function testSetIsActiveAdapterUnauthorized(address caller) public {
        vm.assume(!vault.isAllocator(caller));
        vm.expectRevert(IBluePublicAllocator.Unauthorized.selector);
        vm.prank(caller);
        bluePublicAllocator.setIsActiveAdapter(address(vault), address(adapter), true);
    }

    /* REALLOCATE */

    function testReallocateMovesLiquidity(uint256 assets, uint128 amount) public {
        assets = bound(assets, 1, MAX_TEST_ASSETS);
        amount = uint128(bound(amount, 1, assets));

        _seedMarket1(assets);
        _setIsActiveAdapter(address(adapter), true);
        _setCanPullFromMarket(marketParams1, true);
        _setAbsoluteCap(marketParams2, type(uint256).max);

        uint256 alloc1Before = vault.allocation(id1);
        assertEq(vault.allocation(id2), 0);

        vm.expectEmit();
        emit IBluePublicAllocator.Reallocate(
            rando, address(vault), address(adapter), id1, address(adapter), id2, amount, 0
        );
        _reallocate(amount);

        assertEq(vault.allocation(id1), alloc1Before - amount, "market1");
        assertLe(vault.allocation(id2), amount, "market2 rounds down");
        assertGt(vault.allocation(id2), 0, "market2 supplied");
    }

    function testReallocateAcrossAdaptersMovesLiquidity(uint256 assets, uint128 amount) public {
        assets = bound(assets, 1, MAX_TEST_ASSETS);
        amount = uint128(bound(amount, 1, assets));

        _seedMarket1(assets);
        _setIsActiveAdapter(address(adapter), true);
        _setIsActiveAdapter(address(secondAdapter), true);
        _setCanPullFromMarket(marketParams1, true);
        _setAbsoluteCap(address(secondAdapter), marketParams2, type(uint256).max);

        uint256 alloc1Before = vault.allocation(id1);
        assertEq(vault.allocation(secondAdapterId2), 0);

        vm.expectEmit();
        emit IBluePublicAllocator.Reallocate(
            rando, address(vault), address(adapter), id1, address(secondAdapter), secondAdapterId2, amount, 0
        );
        _reallocateAcrossAdapters(amount);

        assertEq(vault.allocation(id1), alloc1Before - amount, "source market");
        assertLe(vault.allocation(secondAdapterId2), amount, "destination market rounds down");
        assertGt(vault.allocation(secondAdapterId2), 0, "destination market supplied");
    }

    function testReallocateCannotPullFromMarket(uint256 assets, uint128 amount) public {
        assets = bound(assets, 1, MAX_TEST_ASSETS);
        amount = uint128(bound(amount, 1, assets));

        _seedMarket1(assets);
        _setIsActiveAdapter(address(adapter), true);
        _setAbsoluteCap(marketParams2, type(uint256).max);
        // market1 deallocation not enabled.

        vm.expectRevert(IBluePublicAllocator.CannotPullFromMarket.selector);
        _reallocate(amount);
    }

    function testReallocateAbsoluteCapExceeded(uint256 assets, uint128 amount) public {
        assets = bound(assets, 2, MAX_TEST_ASSETS);
        amount = uint128(bound(amount, 2, assets));

        _seedMarket1(assets);
        _setIsActiveAdapter(address(adapter), true);
        _setCanPullFromMarket(marketParams1, true);
        // Absolute cap on market2 is 0: any non-zero resulting allocation must exceed it.
        _setAbsoluteCap(marketParams2, 0);

        vm.expectRevert(IBluePublicAllocator.AbsoluteCapExceeded.selector);
        _reallocate(amount);
    }

    function testReallocateWithinAbsoluteCap(uint256 assets, uint128 amount) public {
        assets = bound(assets, 1, MAX_TEST_ASSETS);
        amount = uint128(bound(amount, 1, assets));

        _seedMarket1(assets);
        _setIsActiveAdapter(address(adapter), true);
        _setCanPullFromMarket(marketParams1, true);
        // Resulting allocation is at most `amount` (Morpho rounds down), so `amount` is a valid cap upper bound.
        _setAbsoluteCap(marketParams2, amount);

        _reallocate(amount);

        assertLe(vault.allocation(id2), bluePublicAllocator.absoluteCap(address(vault), id2), "within cap");
    }

    function testAllocateFromIdle(uint256 assets, uint128 amount) public {
        assets = bound(assets, 1, MAX_TEST_ASSETS);
        amount = uint128(bound(amount, 1, assets));

        vault.deposit(assets, address(this));
        _setIsActiveAdapter(address(adapter), true);
        _setCanPullFromIdle(true);
        _setAbsoluteCap(marketParams2, type(uint256).max);

        vm.expectEmit();
        emit IBluePublicAllocator.AllocateFromIdle(rando, address(vault), address(adapter), id2, amount, 0);
        vm.prank(rando);
        bluePublicAllocator.allocateFromIdle(address(vault), address(adapter), marketParams2, amount, 0);

        assertEq(underlyingToken.balanceOf(address(vault)), assets - amount, "idle");
        assertLe(vault.allocation(id2), amount, "market2 rounds down");
        assertGt(vault.allocation(id2), 0, "market2 supplied");
    }

    function testAllocateFromIdleCannotPullFromIdle(uint256 assets, uint128 amount) public {
        assets = bound(assets, 1, MAX_TEST_ASSETS);
        amount = uint128(bound(amount, 1, assets));

        vault.deposit(assets, address(this));
        _setIsActiveAdapter(address(adapter), true);
        _setAbsoluteCap(marketParams2, type(uint256).max);

        vm.expectRevert(IBluePublicAllocator.CannotPullFromIdle.selector);
        vm.prank(rando);
        bluePublicAllocator.allocateFromIdle(address(vault), address(adapter), marketParams2, amount, 0);
    }

    function testAllocateFromIdleToIdleReverts(uint256 assets, uint128 amount) public {
        assets = bound(assets, 1, MAX_TEST_ASSETS);
        amount = uint128(bound(amount, 1, assets));

        vault.deposit(assets, address(this));
        _setCanPullFromIdle(true);

        vm.expectRevert(IBluePublicAllocator.InactiveAdapter.selector);
        vm.prank(rando);
        bluePublicAllocator.allocateFromIdle(address(vault), address(0), marketParams2, amount, 0);
    }

    function testAllocateFromIdleInactiveAdapter(uint256 assets, uint128 amount) public {
        assets = bound(assets, 1, MAX_TEST_ASSETS);
        amount = uint128(bound(amount, 1, assets));

        vault.deposit(assets, address(this));
        _setCanPullFromIdle(true);
        _setAbsoluteCap(marketParams2, type(uint256).max);

        vm.expectRevert(IBluePublicAllocator.InactiveAdapter.selector);
        vm.prank(rando);
        bluePublicAllocator.allocateFromIdle(address(vault), address(adapter), marketParams2, amount, 0);
    }

    function testReallocateInactiveDeallocateAdapter(uint256 assets, uint128 amount) public {
        assets = bound(assets, 1, MAX_TEST_ASSETS);
        amount = uint128(bound(amount, 1, assets));

        _seedMarket1(assets);
        _setIsActiveAdapter(address(secondAdapter), true);
        _setCanPullFromMarket(marketParams1, true);
        _setAbsoluteCap(address(secondAdapter), marketParams2, type(uint256).max);

        vm.expectRevert(IBluePublicAllocator.InactiveAdapter.selector);
        _reallocateAcrossAdapters(amount);
    }

    function testReallocateInactiveAllocateAdapter(uint256 assets, uint128 amount) public {
        assets = bound(assets, 1, MAX_TEST_ASSETS);
        amount = uint128(bound(amount, 1, assets));

        _seedMarket1(assets);
        _setIsActiveAdapter(address(adapter), true);
        _setCanPullFromMarket(marketParams1, true);
        _setAbsoluteCap(address(secondAdapter), marketParams2, type(uint256).max);

        vm.expectRevert(IBluePublicAllocator.InactiveAdapter.selector);
        _reallocateAcrossAdapters(amount);
    }

    function testReallocateRespectsVaultCaps(uint256 assets, uint128 amount) public {
        assets = bound(assets, 2, MAX_TEST_ASSETS);
        amount = uint128(bound(amount, 2, assets));

        _seedMarket1(assets);
        _setIsActiveAdapter(address(adapter), true);
        _setCanPullFromMarket(marketParams1, true);
        _setAbsoluteCap(marketParams2, type(uint256).max);

        // Vault absolute cap on market2 tightened below the amount so the vault's own allocate reverts first.
        // decreaseAbsoluteCap is not timelocked; the curator can call it directly.
        vm.prank(curator);
        vault.decreaseAbsoluteCap(expectedIdData2[2], amount - 1);

        vm.expectRevert(ErrorsLib.AbsoluteCapExceeded.selector);
        _reallocate(amount);
    }

    /* PENALTY */

    function testSetPenalty(uint64 newPenalty) public {
        newPenalty = uint64(bound(newPenalty, 0, WAD));
        vm.expectEmit();
        emit IBluePublicAllocator.SetPenalty(allocator, address(vault), newPenalty);
        vm.prank(allocator);
        bluePublicAllocator.setPenalty(address(vault), newPenalty);
        (, uint64 penalty_) = bluePublicAllocator.vaultData(address(vault));
        assertEq(penalty_, newPenalty);
    }

    function testSetPenaltyUnauthorized(address caller, uint64 newPenalty) public {
        vm.assume(!vault.isAllocator(caller));
        vm.expectRevert(IBluePublicAllocator.Unauthorized.selector);
        vm.prank(caller);
        bluePublicAllocator.setPenalty(address(vault), newPenalty);
    }

    function testSetPenaltyRevertsWhenAboveWad(uint64 newPenalty) public {
        newPenalty = uint64(bound(newPenalty, WAD + 1, type(uint64).max));
        vm.expectRevert(IBluePublicAllocator.PenaltyTooHigh.selector);
        vm.prank(allocator);
        bluePublicAllocator.setPenalty(address(vault), newPenalty);
    }

    function testReallocateChargesPenalty(uint64 penalty, uint256 assets, uint128 amount) public {
        penalty = uint64(bound(penalty, 1, WAD));
        assets = bound(assets, 1, MAX_TEST_ASSETS);
        amount = uint128(bound(amount, 1, assets));
        vm.prank(allocator);
        bluePublicAllocator.setPenalty(address(vault), penalty);

        _seedMarket1(assets);
        _setIsActiveAdapter(address(adapter), true);
        _setCanPullFromMarket(marketParams1, true);
        _setAbsoluteCap(marketParams2, type(uint256).max);

        uint256 expectedPenaltyAssets = (uint256(amount) * penalty + WAD - 1) / WAD;

        deal(address(underlyingToken), rando, expectedPenaltyAssets);
        vm.startPrank(rando);
        underlyingToken.approve(address(bluePublicAllocator), expectedPenaltyAssets);
        vm.expectEmit();
        emit IBluePublicAllocator.Reallocate(
            rando, address(vault), address(adapter), id1, address(adapter), id2, amount, expectedPenaltyAssets
        );
        bluePublicAllocator.reallocate(
            address(vault), address(adapter), marketParams1, address(adapter), marketParams2, amount, penalty
        );
        vm.stopPrank();

        assertEq(underlyingToken.balanceOf(rando), 0);
        assertEq(underlyingToken.balanceOf(address(vault)), expectedPenaltyAssets, "penalty donated to the vault");
        assertEq(underlyingToken.balanceOf(address(bluePublicAllocator)), 0);
    }

    function testAllocateFromIdleChargesPenalty(uint64 penalty, uint256 assets, uint128 amount) public {
        penalty = uint64(bound(penalty, 1, WAD));
        assets = bound(assets, 1, MAX_TEST_ASSETS);
        amount = uint128(bound(amount, 1, assets));
        vm.prank(allocator);
        bluePublicAllocator.setPenalty(address(vault), penalty);

        vault.deposit(assets, address(this));
        _setIsActiveAdapter(address(adapter), true);
        _setCanPullFromIdle(true);
        _setAbsoluteCap(marketParams2, type(uint256).max);

        uint256 expectedPenaltyAssets = (uint256(amount) * penalty + WAD - 1) / WAD;

        deal(address(underlyingToken), rando, expectedPenaltyAssets);
        vm.startPrank(rando);
        underlyingToken.approve(address(bluePublicAllocator), expectedPenaltyAssets);
        vm.expectEmit();
        emit IBluePublicAllocator.AllocateFromIdle(
            rando, address(vault), address(adapter), id2, amount, expectedPenaltyAssets
        );
        bluePublicAllocator.allocateFromIdle(address(vault), address(adapter), marketParams2, amount, penalty);
        vm.stopPrank();

        assertEq(underlyingToken.balanceOf(rando), 0);
        assertEq(
            underlyingToken.balanceOf(address(vault)),
            assets - amount + expectedPenaltyAssets,
            "penalty donated to the vault"
        );
        assertEq(underlyingToken.balanceOf(address(bluePublicAllocator)), 0);
    }

    function testReallocatePenaltyNotPaid(uint64 penalty, uint256 assets, uint128 amount) public {
        penalty = uint64(bound(penalty, 1, WAD));
        assets = bound(assets, 1, MAX_TEST_ASSETS);
        amount = uint128(bound(amount, 1, assets));
        vm.prank(allocator);
        bluePublicAllocator.setPenalty(address(vault), penalty);

        _seedMarket1(assets);
        _setIsActiveAdapter(address(adapter), true);
        _setCanPullFromMarket(marketParams1, true);
        _setAbsoluteCap(marketParams2, type(uint256).max);

        vm.expectRevert(ErrorsLib.TransferFromReverted.selector);
        _reallocate(amount);
    }

    function testReallocateIncorrectPenalty(uint64 penalty, uint64 wrongPenalty, uint128 amount) public {
        penalty = uint64(bound(penalty, 0, WAD));
        wrongPenalty = uint64(bound(wrongPenalty, 0, WAD));
        vm.assume(wrongPenalty != penalty);
        vm.prank(allocator);
        bluePublicAllocator.setPenalty(address(vault), penalty);

        vm.expectRevert(IBluePublicAllocator.IncorrectPenalty.selector);
        vm.prank(rando);
        bluePublicAllocator.reallocate(
            address(vault), address(adapter), marketParams1, address(adapter), marketParams2, amount, wrongPenalty
        );
    }

    function testAllocateFromIdleIncorrectPenalty(uint64 penalty, uint64 wrongPenalty, uint128 amount) public {
        penalty = uint64(bound(penalty, 0, WAD));
        wrongPenalty = uint64(bound(wrongPenalty, 0, WAD));
        vm.assume(wrongPenalty != penalty);
        vm.prank(allocator);
        bluePublicAllocator.setPenalty(address(vault), penalty);

        vm.expectRevert(IBluePublicAllocator.IncorrectPenalty.selector);
        vm.prank(rando);
        bluePublicAllocator.allocateFromIdle(address(vault), address(adapter), marketParams2, amount, wrongPenalty);
    }
}
