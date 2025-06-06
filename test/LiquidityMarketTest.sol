// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import "./BaseTest.sol";

contract LiquidityMarketTest is BaseTest {
    using MathLib for uint256;

    AdapterMock public adapter;
    uint256 internal constant MAX_TEST_ASSETS = 1e18 ether;
    uint256 internal constant MAX_TEST_SHARES = 1e18 ether;

    function setUp() public override {
        super.setUp();

        adapter = new AdapterMock(address(vault));

        deal(address(underlyingToken), address(this), type(uint256).max);
        underlyingToken.approve(address(vault), type(uint256).max);

        vm.prank(curator);
        vault.submit(abi.encodeCall(IVaultV2.setIsAdapter, (address(adapter), true)));
        vault.setIsAdapter(address(adapter), true);

        increaseAbsoluteCap("id-0", type(uint128).max);
        increaseAbsoluteCap("id-1", type(uint128).max);
        increaseRelativeCap("id-0", WAD);
        increaseRelativeCap("id-1", WAD);
    }

    function testLiquidityMarketDeposit(bytes memory data, uint256 assets) public {
        assets = bound(assets, 0, MAX_TEST_ASSETS);

        vm.prank(allocator);
        vault.setLiquidityMarket(address(adapter), data);

        vault.deposit(assets, address(this));

        assertEq(adapter.recordedAllocateData(), data);
        assertEq(adapter.recordedAllocateAssets(), assets);
        assertEq(underlyingToken.balanceOf(address(adapter)), assets);
    }

    function testLiquidityMarketMint(bytes memory data, uint256 shares) public {
        shares = bound(shares, 0, MAX_TEST_SHARES);

        vm.prank(allocator);
        vault.setLiquidityMarket(address(adapter), data);

        uint256 assets = vault.mint(shares, address(this));

        assertEq(adapter.recordedAllocateData(), data);
        assertEq(adapter.recordedAllocateAssets(), assets);
        assertEq(underlyingToken.balanceOf(address(adapter)), assets);
    }

    function testLiquidityMarketWithdraw(bytes memory data, uint256 deposit) public {
        address receiver = makeAddr("receiver");
        deposit = bound(deposit, 1, MAX_TEST_ASSETS);

        vm.prank(allocator);
        vault.setLiquidityMarket(address(adapter), data);

        vault.deposit(deposit, address(this));
        uint256 assets = vault.previewRedeem(vault.balanceOf(address(this)));
        vault.withdraw(assets, receiver, address(this));

        assertEq(adapter.recordedDeallocateData(), data);
        assertEq(adapter.recordedDeallocateAssets(), assets);
        assertEq(underlyingToken.balanceOf(receiver), assets);
    }

    function testLiquidityMarketRedeem(bytes memory data, uint256 deposit) public {
        address receiver = makeAddr("receiver");
        deposit = bound(deposit, 1, MAX_TEST_ASSETS);

        vm.prank(allocator);
        vault.setLiquidityMarket(address(adapter), data);

        vault.deposit(deposit, address(this));
        uint256 assets = vault.redeem(vault.balanceOf(address(this)), receiver, address(this));

        assertEq(adapter.recordedDeallocateData(), data);
        assertEq(adapter.recordedDeallocateAssets(), assets);
        assertEq(underlyingToken.balanceOf(receiver), assets);
    }

    function testAvoidLiquidityMarketDeposit() public {
        vm.prank(allocator);
        vault.setLiquidityMarket(address(adapter), hex"");

        vault.deposit{gas: 200_000}(1, address(this));
        assertEq(adapter.recordedAllocateAssets(), 0);
    }
}
