// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Morpho Association
pragma solidity ^0.8.0;

import "./BaseTest.sol";

contract LiquidityAdapterTest is BaseTest {
    using MathLib for uint256;

    AdapterMock public adapter;
    uint256 internal MAX_TEST_ASSETS;
    uint256 internal MAX_TEST_SHARES;

    function setUp() public override {
        super.setUp();

        MAX_TEST_ASSETS = 10 ** min(18 + underlyingToken.decimals(), 36);
        MAX_TEST_SHARES = 10 ** min(18 + underlyingToken.decimals(), 36);

        adapter = new AdapterMock(address(vault));

        deal(address(underlyingToken), address(this), type(uint256).max);
        underlyingToken.approve(address(vault), type(uint256).max);

        vm.prank(curator);
        vault.submit(abi.encodeCall(IVaultV2.addAdapter, (address(adapter))));
        vault.addAdapter(address(adapter));

        increaseAbsoluteCap("id-0", type(uint128).max);
        increaseAbsoluteCap("id-1", type(uint128).max);
        increaseRelativeCap("id-0", WAD);
        increaseRelativeCap("id-1", WAD);
    }

    function testLiquidityAdapterDeposit(bytes memory data, uint256 assets) public {
        assets = bound(assets, 0, MAX_TEST_ASSETS);

        vm.prank(allocator);
        vault.setLiquidityAdapterAndData(address(adapter), data);

        vault.deposit(assets, address(this));

        assertEq(adapter.recordedAllocateData(), data);
        assertEq(adapter.recordedAllocateAssets(), assets);
        assertEq(underlyingToken.balanceOf(address(adapter)), assets);
    }

    function testLiquidityAdapterMint(bytes memory data, uint256 shares) public {
        shares = bound(shares, 0, MAX_TEST_SHARES);

        vm.prank(allocator);
        vault.setLiquidityAdapterAndData(address(adapter), data);

        uint256 assets = vault.mint(shares, address(this));

        assertEq(adapter.recordedAllocateData(), data);
        assertEq(adapter.recordedAllocateAssets(), assets);
        assertEq(underlyingToken.balanceOf(address(adapter)), assets);
    }

    function testLiquidityAdapterWithdraw(bytes memory data, uint256 deposit) public {
        address receiver = makeAddr("receiver");
        deposit = bound(deposit, 1, MAX_TEST_ASSETS);

        vm.prank(allocator);
        vault.setLiquidityAdapterAndData(address(adapter), data);

        vault.deposit(deposit, address(this));
        uint256 assets = vault.previewRedeem(vault.balanceOf(address(this)));
        vault.withdraw(assets, receiver, address(this));

        assertEq(adapter.recordedDeallocateData(), data);
        assertEq(adapter.recordedDeallocateAssets(), assets);
        assertEq(underlyingToken.balanceOf(receiver), assets);
    }

    function testLiquidityAdapterRedeem(bytes memory data, uint256 deposit) public {
        address receiver = makeAddr("receiver");
        deposit = bound(deposit, 1, MAX_TEST_ASSETS);

        vm.prank(allocator);
        vault.setLiquidityAdapterAndData(address(adapter), data);

        vault.deposit(deposit, address(this));
        uint256 assets = vault.redeem(vault.balanceOf(address(this)), receiver, address(this));

        assertEq(adapter.recordedDeallocateData(), data);
        assertEq(adapter.recordedDeallocateAssets(), assets);
        assertEq(underlyingToken.balanceOf(receiver), assets);
    }
}
