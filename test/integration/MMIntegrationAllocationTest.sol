// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import "./MMIntegrationTest.sol";

contract MMIntegrationAllocationTest is MMIntegrationTest {
    using MorphoBalancesLib for IMorpho;

    address internal immutable borrower = makeAddr("borrower");

    uint256 internal initialInIdle = 0.3e18;
    uint256 internal initialInMM = 0.7e18;
    uint256 internal initialTotal = 1e18;

    function setUp() public virtual override {
        super.setUp();

        assertEq(initialTotal, initialInIdle + initialInMM);

        vault.deposit(initialTotal, address(this));

        setSupplyQueueAllMarkets();

        vm.prank(allocator);
        vault.allocate(address(metaMorphoAdapter), hex"", initialInMM);

        assertEq(underlyingToken.balanceOf(address(vault)), initialInIdle);
        assertEq(underlyingToken.balanceOf(address(morpho)), initialInMM);
    }

    function testDeallocateLessThanAllocated(uint256 assets) public {
        assets = bound(assets, 0, initialInMM);

        vm.prank(allocator);
        vault.deallocate(address(metaMorphoAdapter), hex"", assets);

        assertEq(underlyingToken.balanceOf(address(vault)), initialInIdle + assets);
        assertEq(underlyingToken.balanceOf(address(morpho)), initialInMM - assets);
    }

    function testDeallocateMoreThanAllocated(uint256 assets) public {
        assets = bound(assets, initialInMM + 1, MAX_TEST_ASSETS);

        vm.prank(allocator);
        vm.expectRevert();
        vault.deallocate(address(metaMorphoAdapter), hex"", assets);
    }

    function testDeallocateNoLiquidity(uint256 assets) public {
        assets = bound(assets, initialInIdle + 1, initialTotal);
        vm.prank(allocator);
        vault.setLiquidityAdapter(address(metaMorphoAdapter));

        // Remove liquidity by borrowing.
        deal(address(collateralToken), borrower, type(uint256).max);
        vm.startPrank(borrower);
        collateralToken.approve(address(morpho), type(uint256).max);
        morpho.supplyCollateral(allMarketParams[0], 2 * initialInMM, borrower, hex"");
        morpho.borrow(allMarketParams[0], initialInMM, 0, borrower, borrower);
        vm.stopPrank();
        assertEq(underlyingToken.balanceOf(address(morpho)), 0);

        vm.prank(allocator);
        vm.expectRevert();
        vault.deallocate(address(metaMorphoAdapter), hex"", assets);
    }

    function testAllocateLessThanIdle(uint256 assets) public {
        assets = bound(assets, 0, initialInIdle);

        vm.prank(allocator);
        vault.allocate(address(metaMorphoAdapter), hex"", assets);

        assertEq(underlyingToken.balanceOf(address(vault)), initialInIdle - assets);
        assertEq(underlyingToken.balanceOf(address(morpho)), initialInMM + assets);
    }

    function testAllocateMoreThanIdle(uint256 assets) public {
        assets = bound(assets, initialInIdle + 1, MAX_TEST_ASSETS);

        vm.prank(allocator);
        vm.expectRevert();
        vault.allocate(address(metaMorphoAdapter), hex"", assets);
    }

    function testAllocateMoreThanMetaMorphoCap(uint256 assets) public {
        assets = bound(assets, 1, MAX_TEST_ASSETS);

        // Put all caps to the limit.
        vm.startPrank(mmCurator);
        metaMorpho.submitCap(allMarketParams[0], initialInMM);
        for (uint256 i = 1; i < MM_NB_MARKETS; i++) {
            metaMorpho.submitCap(allMarketParams[i], 0);
        }
        vm.stopPrank();

        vm.prank(allocator);
        vm.expectRevert();
        vault.allocate(address(metaMorphoAdapter), hex"", assets);
    }
}
