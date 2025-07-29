// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Morpho Association
pragma solidity ^0.8.0;

import "./MorphoVaultV1IntegrationTest.sol";
import {OnchainVic} from "../../src/vic/OnchainVic.sol";

contract OnchainVicIntegrationTest is MorphoVaultV1IntegrationTest {
    using MathLib for uint256;

    address internal onchainVic;

    function setUp() public override {
        super.setUp();

        onchainVic = address(new OnchainVic(address(vault)));

        vm.prank(curator);
        vault.submit(abi.encodeCall(IVaultV2.setVic, (onchainVic)));
        vault.setVic(onchainVic);

        deal(address(underlyingToken), address(this), type(uint256).max);
        underlyingToken.approve(address(morphoVaultV1), type(uint256).max);
        underlyingToken.approve(address(morpho), type(uint256).max);

        deal(address(collateralToken), address(this), type(uint256).max);
        collateralToken.approve(address(morpho), type(uint256).max);
    }

    function testOnchainVic(uint256 assets, uint256 elapsed) public {
        assets = bound(assets, 1, MAX_TEST_ASSETS);
        elapsed = bound(elapsed, 1, 10 * 52 weeks);

        setSupplyQueueAllMarkets();
        vm.prank(allocator);
        vault.setLiquidityAdapterAndData(address(morphoVaultV1Adapter), hex"");
        setMorphoVaultV1Cap(allMarketParams[0], type(uint184).max);

        vault.deposit(assets, address(this));
        assertEq(vault.previewRedeem(vault.balanceOf(address(this))), assets);
        assertEq(morphoVaultV1.previewRedeem(morphoVaultV1.balanceOf(address(morphoVaultV1Adapter))), assets);

        assertEq(vault.totalAssets(), assets, "total assets before");

        // Generate some interest.
        morpho.supplyCollateral(allMarketParams[0], 2 * assets, address(this), hex"");
        morpho.borrow(allMarketParams[0], assets, 0, address(this), address(1));
        skip(elapsed);
        uint256 newAssets = morphoVaultV1.previewRedeem(morphoVaultV1.balanceOf(address(morphoVaultV1Adapter)));
        uint256 interest = newAssets - assets;
        vm.assume(interest <= assets.mulDivDown(MAX_RATE_PER_SECOND, WAD) * elapsed);

        assertEq(vault.totalAssets(), assets + interest, "total assets");
        assertApproxEqRel(
            vault.previewRedeem(vault.balanceOf(address(this))), assets + interest, 0.00001e18, "preview redeem"
        );
    }

    function testInterestPerSecondDonationIdle(uint256 deposit, uint256 interest, uint256 elapsed) public {
        deposit = bound(deposit, 1, MAX_TEST_ASSETS);
        interest = bound(interest, 1, MAX_TEST_ASSETS);
        elapsed = bound(elapsed, 1, 2 ** 63);

        setSupplyQueueAllMarkets();
        vm.prank(allocator);
        vault.setLiquidityAdapterAndData(address(morphoVaultV1Adapter), hex"");
        setMorphoVaultV1Cap(allMarketParams[0], type(uint184).max);

        vault.deposit(deposit, address(this));
        underlyingToken.transfer(address(vault), interest);
        skip(elapsed);
        vm.assume(interest <= deposit.mulDivDown(MAX_RATE_PER_SECOND, WAD) * elapsed);

        assertEq(vault.totalAssets(), deposit + interest, "wrong total assets");
    }

    function testInterestPerSecondDonationInKind(uint256 deposit, uint256 interest, uint256 elapsed) public {
        deposit = bound(deposit, 1, MAX_TEST_ASSETS);
        interest = bound(interest, 1, MAX_TEST_ASSETS);
        elapsed = bound(elapsed, 1, 2 ** 63);

        setSupplyQueueAllMarkets();
        vm.prank(allocator);
        vault.setLiquidityAdapterAndData(address(morphoVaultV1Adapter), hex"");
        setMorphoVaultV1Cap(allMarketParams[0], type(uint184).max);

        vault.deposit(deposit, address(this));
        deal(address(morphoVaultV1), address(morphoVaultV1Adapter), interest);
        skip(elapsed);

        assertEq(vault.totalAssets(), deposit, "the donation is not ignored");
    }
}
