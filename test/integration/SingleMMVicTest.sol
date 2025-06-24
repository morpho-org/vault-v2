// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Morpho Association
pragma solidity ^0.8.0;

import "./MMIntegrationTest.sol";
import {SingleMetaMorphoVic} from "../../src/vic/SingleMetaMorphoVic.sol";

contract SingleMMVicTest is MMIntegrationTest {
    SingleMetaMorphoVic internal singleMetaMorphoVic;

    function setUp() public override {
        super.setUp();

        singleMetaMorphoVic = new SingleMetaMorphoVic(address(metaMorphoAdapter));

        vm.prank(curator);
        vault.submit(abi.encodeCall(IVaultV2.setVic, (address(singleMetaMorphoVic))));
        vault.setVic(address(singleMetaMorphoVic));
    }

    function testSingleMMVic(uint256 assets, uint256 elapsed) public {
        assets = bound(assets, 1, MAX_TEST_ASSETS);
        elapsed = bound(elapsed, 1, 10 * 52 weeks);

        setSupplyQueueAllMarkets();
        vm.prank(allocator);
        vault.setLiquidityMarket(address(metaMorphoAdapter), hex"");
        setMetaMorphoCap(allMarketParams[0], type(uint184).max);

        vault.deposit(assets, address(this));
        assertEq(vault.previewRedeem(vault.balanceOf(address(this))), assets);
        assertEq(metaMorpho.previewRedeem(metaMorpho.balanceOf(address(metaMorphoAdapter))), assets);

        uint256 totalAssetsBefore = vault.totalAssets();

        // Generate some interest.
        deal(address(collateralToken), address(this), 2 * assets);
        collateralToken.approve(address(morpho), 2 * assets);
        morpho.supplyCollateral(allMarketParams[0], 2 * assets, address(this), hex"");
        morpho.borrow(allMarketParams[0], assets, 0, address(this), address(1));
        skip(elapsed);
        uint256 newAssets = metaMorpho.previewRedeem(metaMorpho.balanceOf(address(metaMorphoAdapter)));
        uint256 interestPerSecond = (newAssets - assets) / elapsed;
        vm.assume(interestPerSecond <= assets * MAX_RATE_PER_SECOND / WAD);

        assertEq(vault.totalAssets(), totalAssetsBefore + interestPerSecond * elapsed, "total assets");
        assertApproxEqRel(
            vault.previewRedeem(vault.balanceOf(address(this))),
            totalAssetsBefore + interestPerSecond * elapsed,
            0.00001e18,
            "preview redeem"
        );
    }
}
