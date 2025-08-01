// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Morpho Association
pragma solidity ^0.8.0;

import "./MorphoMarketV1IntegrationTest.sol";
import {MathLib} from "../../src/libraries/MathLib.sol";

contract MorphoMarketV1IntegrationIkrTest is MorphoMarketV1IntegrationTest {
    using MathLib for uint256;
    using MorphoBalancesLib for IMorpho;

    uint256 internal constant MIN_IKR_TEST_ASSETS = 1;
    uint256 internal constant MAX_IKR_TEST_ASSETS = 1e18;

    uint256 internal constant penalty = 0.01e18;

    address internal immutable receiver = makeAddr("receiver");
    address internal immutable borrower = makeAddr("borrower");

    function setUp() public virtual override {
        super.setUp();

        vm.prank(curator);
        vault.submit(abi.encodeCall(IVaultV2.setForceDeallocatePenalty, (address(adapter), penalty)));
        vault.setForceDeallocatePenalty(address(adapter), penalty);
    }

    function setUpAssets(uint256 assets) internal {
        vault.deposit(assets, address(this));

        vm.prank(allocator);
        vault.allocate(address(adapter), abi.encode(marketParams1), assets);

        assertEq(underlyingToken.balanceOf(address(morpho)), assets);

        // Remove liquidity by borrowing.
        deal(address(collateralToken), borrower, type(uint256).max);
        vm.startPrank(borrower);
        collateralToken.approve(address(morpho), type(uint256).max);
        morpho.supplyCollateral(marketParams1, 2 * assets, borrower, hex"");
        morpho.borrow(marketParams1, assets, 0, borrower, borrower);
        vm.stopPrank();
        assertEq(underlyingToken.balanceOf(address(morpho)), 0);

        // Assume that the depositor has no other asset.
        deal(address(underlyingToken), address(this), 0);

        assertEq(vault.previewRedeem(vault.balanceOf(address(this))), assets);
    }

    function testCantWithdraw(uint256 assets) public {
        assets = bound(assets, MIN_IKR_TEST_ASSETS, MAX_IKR_TEST_ASSETS);
        setUpAssets(assets);

        vm.expectRevert();
        vault.withdraw(assets, receiver, address(this));
    }

    function testInKindRedemption(uint256 assets) public {
        assets = bound(assets, MIN_IKR_TEST_ASSETS, MAX_IKR_TEST_ASSETS);
        setUpAssets(assets);

        uint256 penaltyAssets = assets.mulDivUp(penalty, WAD);

        // Normal withdraw fails
        vm.prank(allocator);
        vault.setLiquidityAdapterAndData(address(adapter), abi.encode(marketParams1));

        vm.expectRevert();
        vault.withdraw(assets, address(this), address(this));

        // Simulate a flashloan.
        deal(address(underlyingToken), address(this), assets);
        underlyingToken.approve(address(morpho), type(uint256).max);
        morpho.supply(marketParams1, assets, 0, address(this), hex"");
        vault.forceDeallocate(address(adapter), abi.encode(marketParams1), assets, address(this));
        assertEq(vault.allocation(keccak256(expectedIdData1[2])), 0, "allocation(2)");

        vault.withdraw(assets - penaltyAssets, address(this), address(this));

        // No assets left after reimbursing the flashloan.
        assertEq(underlyingToken.balanceOf(address(this)), assets - penaltyAssets, "balanceOf(this)");
        // No assets left in the vault
        assertApproxEqAbs(underlyingToken.balanceOf(address(vault)), penaltyAssets, 1);
        // No assets left as shares in the vault.
        uint256 assetsLeftInVault = vault.previewRedeem(vault.balanceOf(address(this)));
        assertApproxEqAbs(assetsLeftInVault, 0, 1, "assetsLeftInVault");
        // Equivalent position in the market.
        uint256 expectedAssets = morpho.expectedSupplyAssets(marketParams1, address(this));
        assertEq(expectedAssets, assets, "expectedAssets");
    }
}
