// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Morpho Association
pragma solidity ^0.8.0;

import "./MorphoVaultV1_1IntegrationTest.sol";
import {MathLib} from "../../src/libraries/MathLib.sol";

contract MorphoVaultV1_1IntegrationIkrTest is MorphoVaultV1_1IntegrationTest {
    using MathLib for uint256;
    using MorphoBalancesLib for IMorpho;

    uint256 internal constant MIN_IKR_TEST_ASSETS = 1;
    uint256 internal constant MAX_IKR_TEST_ASSETS = 1e18;

    uint256 internal constant penalty = 0.01e18;

    address internal immutable receiver = makeAddr("receiver");
    address internal immutable borrower = makeAddr("borrower");

    function setUp() public virtual override {
        super.setUp();

        setSupplyQueueAllMarkets();

        vm.startPrank(curator);
        vault.submit(abi.encodeCall(IVaultV2.setForceDeallocatePenalty, (address(morphoVaultV1Adapter), penalty)));
        vault.setForceDeallocatePenalty(address(morphoVaultV1Adapter), penalty);
        vm.stopPrank();
    }

    function setUpAssets(uint256 assets) internal {
        vault.deposit(assets, address(this));

        vm.prank(allocator);
        vault.allocate(address(morphoVaultV1Adapter), hex"", assets);

        assertEq(underlyingToken.balanceOf(address(morpho)), assets);

        // Remove liquidity by borrowing.
        deal(address(collateralToken), borrower, type(uint256).max);
        vm.startPrank(borrower);
        collateralToken.approve(address(morpho), type(uint256).max);
        morpho.supplyCollateral(allMarketParams[0], 2 * assets, borrower, hex"");
        morpho.borrow(allMarketParams[0], assets, 0, borrower, borrower);
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

    // This method to redeem in-kind is not always available, notably when Morpho Vault v1 deposits are paused.
    // In that case, use the redemption of Morpho Market v1 shares.
    function testRedeemSharesOfMorphoVaultV1_1(uint256 assets) public {
        assets = bound(assets, MIN_IKR_TEST_ASSETS, MAX_IKR_TEST_ASSETS);
        setUpAssets(assets);

        uint256 penaltyAssets = assets.mulDivUp(penalty, WAD);

        // Simulate a flashloan.
        deal(address(underlyingToken), address(this), assets);
        underlyingToken.approve(address(morphoVaultV1), type(uint256).max);
        morphoVaultV1.deposit(assets, address(this));
        vault.forceDeallocate(address(morphoVaultV1Adapter), hex"", assets, address(this));
        vault.withdraw(assets - penaltyAssets, address(this), address(this));

        // No assets left after reimbursing the flashloan.
        assertEq(underlyingToken.balanceOf(address(this)), assets - penaltyAssets, "balanceOf(this)");
        // No assets left as shares in the vault.
        uint256 assetsLeftInVault = vault.previewRedeem(vault.balanceOf(address(this)));
        assertApproxEqAbs(assetsLeftInVault, 0, 1, "assetsLeftInVault");
        // Equivalent position in Morpho Vault v1.
        uint256 shares = morphoVaultV1.balanceOf(address(this));
        uint256 expectedAssets = morphoVaultV1.previewRedeem(shares);
        // Note that the penalty cannot be paid with the position (makes sense).
        assertEq(expectedAssets, assets, "expectedAssets");
    }

    function testRedeemSharesOfMorphoMarketV1(uint256 assets) public {
        assets = bound(assets, MIN_IKR_TEST_ASSETS, MAX_IKR_TEST_ASSETS);
        setUpAssets(assets);

        // Pause deposits on Morpho Vault v1.
        Id[] memory emptySupplyQueue = new Id[](0);
        vm.prank(mmAllocator);
        morphoVaultV1.setSupplyQueue(emptySupplyQueue);

        uint256 penaltyAssets = assets.mulDivUp(penalty, WAD);

        // Simulate a flashloan.
        deal(address(underlyingToken), address(this), assets);
        underlyingToken.approve(address(morpho), type(uint256).max);
        morpho.supply(allMarketParams[0], assets, 0, address(this), hex"");
        vault.forceDeallocate(address(morphoVaultV1Adapter), hex"", assets, address(this));
        vault.withdraw(assets - penaltyAssets, address(this), address(this));

        // No assets left after reimbursing the flashloan.
        assertEq(underlyingToken.balanceOf(address(this)), assets - penaltyAssets, "balanceOf(this)");
        // No assets left as shares in the vault.
        uint256 assetsLeftInVault = vault.previewRedeem(vault.balanceOf(address(this)));
        assertApproxEqAbs(assetsLeftInVault, 0, 1, "assetsLeftInVault");
        // Equivalent position in the market.
        uint256 expectedAssets = morpho.expectedSupplyAssets(allMarketParams[0], address(this));
        assertEq(expectedAssets, assets);
    }
}
