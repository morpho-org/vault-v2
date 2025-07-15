// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Morpho Association
pragma solidity ^0.8.0;

import "./MorphoVaultV1IntegrationTest.sol";
import {SingleMorphoVaultV1Vic} from "../../src/vic/SingleMorphoVaultV1Vic.sol";
import {ISingleMorphoVaultV1Vic} from "../../src/vic/interfaces/ISingleMorphoVaultV1Vic.sol";

contract SingleMorphoVaultV1VicIntegrationTest is MorphoVaultV1IntegrationTest {
    ISingleMorphoVaultV1Vic internal singleMorphoVaultV1Vic;

    function setUp() public override {
        super.setUp();

        singleMorphoVaultV1Vic =
            ISingleMorphoVaultV1Vic(address(new SingleMorphoVaultV1Vic(address(morphoVaultV1Adapter))));

        vm.prank(curator);
        vault.submit(abi.encodeCall(IVaultV2.setVic, (address(singleMorphoVaultV1Vic))));
        vault.setVic(address(singleMorphoVaultV1Vic));

        deal(address(underlyingToken), address(this), type(uint256).max);
        underlyingToken.approve(address(morphoVaultV1), type(uint256).max);
        underlyingToken.approve(address(morpho), type(uint256).max);

        deal(address(collateralToken), address(this), type(uint256).max);
        collateralToken.approve(address(morpho), type(uint256).max);
    }

    function testSingleMorphoVaultV1Vic(uint256 assets, uint256 elapsed) public {
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
        uint256 interestPerSecond = (newAssets - assets) / elapsed;
        vm.assume(interestPerSecond <= assets * MAX_RATE_PER_SECOND / WAD);

        assertEq(vault.totalAssets(), assets + interestPerSecond * elapsed, "total assets");
        assertApproxEqRel(
            vault.previewRedeem(vault.balanceOf(address(this))),
            assets + interestPerSecond * elapsed,
            0.00001e18,
            "preview redeem"
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
        vm.assume(interest / elapsed <= deposit * MAX_RATE_PER_SECOND / WAD);

        assertEq(vault.totalAssets(), deposit + interest / elapsed * elapsed, "wrong total assets");
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
