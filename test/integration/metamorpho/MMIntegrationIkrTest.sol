// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import "./MMIntegrationTest.sol";
import {MathLib} from "../../../src/libraries/MathLib.sol";

contract MMIntegrationIkrTest is MMIntegrationTest {
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
        vault.submit(abi.encodeCall(IVaultV2.setForceDeallocatePenalty, (address(metaMorphoAdapter), penalty)));
        vault.setForceDeallocatePenalty(address(metaMorphoAdapter), penalty);
        vm.stopPrank();
    }

    function setUpAssets(uint256 assets) internal {
        vault.deposit(assets, address(this));

        vm.prank(allocator);
        vault.allocate(address(metaMorphoAdapter), hex"", assets);

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

    // The optimal number of assets to deallocate in order to IKR max.
    function optimalDeallocateAssets(uint256 assets) internal pure returns (uint256) {
        return assets.mulDivDown(WAD, WAD + penalty);
    }

    function _list(address input) internal pure returns (address[] memory) {
        address[] memory list = new address[](1);
        list[0] = input;
        return list;
    }

    function _list(bytes memory input) internal pure returns (bytes[] memory) {
        bytes[] memory list = new bytes[](1);
        list[0] = input;
        return list;
    }

    function _list(uint256 input) internal pure returns (uint256[] memory) {
        uint256[] memory list = new uint256[](1);
        list[0] = input;
        return list;
    }

    function testCantWithdraw(uint256 assets) public {
        assets = bound(assets, MIN_IKR_TEST_ASSETS, MAX_IKR_TEST_ASSETS);
        setUpAssets(assets);

        vm.expectRevert();
        vault.withdraw(assets, receiver, address(this));
    }

    // Note that this method to redeem in-kind is not always available: it is possible that MM deposits are paused.
    // In that case, use the redemption of Morpho Blue shares.
    function testRedeemSharesOfMM(uint256 assets) public {
        assets = bound(assets, MIN_IKR_TEST_ASSETS, MAX_IKR_TEST_ASSETS);
        setUpAssets(assets);

        uint256 deallocatedAssets = optimalDeallocateAssets(assets);
        // Simulate a flashloan.
        deal(address(underlyingToken), address(this), deallocatedAssets);
        underlyingToken.approve(address(metaMorpho), type(uint256).max);
        metaMorpho.deposit(deallocatedAssets, address(this));
        vault.forceDeallocate(_list(address(metaMorphoAdapter)), _list(hex""), _list(deallocatedAssets), address(this));
        vault.withdraw(deallocatedAssets, address(this), address(this));

        // No assets left after reimbursing the flashloan.
        assertEq(underlyingToken.balanceOf(address(this)), deallocatedAssets);
        // No assets left as shares in the vault.
        uint256 assetsLeftInVault = vault.previewRedeem(vault.balanceOf(address(this)));
        assertApproxEqAbs(assetsLeftInVault, 0, 1);
        // Equivalent position in MM.
        uint256 shares = metaMorpho.balanceOf(address(this));
        uint256 expectedAssets = metaMorpho.previewRedeem(shares);
        assertEq(expectedAssets, deallocatedAssets);
    }

    function testRedeemSharesOfBlue(uint256 assets) public {
        assets = bound(assets, MIN_IKR_TEST_ASSETS, MAX_IKR_TEST_ASSETS);
        setUpAssets(assets);

        // Pause deposits on MM.
        Id[] memory emptySupplyQueue = new Id[](0);
        vm.prank(mmAllocator);
        metaMorpho.setSupplyQueue(emptySupplyQueue);

        uint256 deallocatedAssets = optimalDeallocateAssets(assets);
        vm.assume(deallocatedAssets > 0);
        // Simulate a flashloan.
        deal(address(underlyingToken), address(this), deallocatedAssets);
        underlyingToken.approve(address(morpho), type(uint256).max);
        morpho.supply(allMarketParams[0], deallocatedAssets, 0, address(this), hex"");
        vault.forceDeallocate(_list(address(metaMorphoAdapter)), _list(hex""), _list(deallocatedAssets), address(this));
        vault.withdraw(deallocatedAssets, address(this), address(this));

        // No assets left after reimbursing the flashloan.
        assertEq(underlyingToken.balanceOf(address(this)), deallocatedAssets);
        // No assets left as shares in the vault.
        uint256 assetsLeftInVault = vault.previewRedeem(vault.balanceOf(address(this)));
        assertApproxEqAbs(assetsLeftInVault, 0, 1);
        // Equivalent position in Blue.
        uint256 expectedAssets = morpho.expectedSupplyAssets(allMarketParams[0], address(this));
        assertEq(expectedAssets, deallocatedAssets);
    }
}
