// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import "./BaseTest.sol";

uint256 constant MAX_TEST_AMOUNT = 1e36;

import {MockAdapter} from "./RealizeLossTest.sol";

contract RealizeFunctionTest is BaseTest {
    using MathLib for uint256;

    address internal adapter;
    bytes internal idData;
    bytes32 internal id;
    bytes32[] internal ids;
    address realizer;

    function setUp() public override {
        super.setUp();

        realizer = makeAddr("realizer");
        adapter = address(new MockAdapter());

        vm.prank(curator);
        vault.submit(abi.encodeWithSelector(IVaultV2.setIsAdapter.selector, adapter, true));
        vault.setIsAdapter(adapter, true);

        deal(address(underlyingToken), address(this), type(uint256).max);
        underlyingToken.approve(address(vault), type(uint256).max);

        ids = new bytes32[](1);
        idData = "id";
        id = keccak256(idData);
        ids[0] = id;
        MockAdapter(adapter).setIds(ids);
    }

    function setupRealization(uint256 assets) public {
        vault.deposit(assets, address(this));
        assertEq(underlyingToken.balanceOf(address(vault)), assets, "Initial vault balance incorrect");
        assertEq(underlyingToken.balanceOf(adapter), 0, "Initial adapter balance incorrect");
        assertEq(vault.allocation(id), 0, "Initial allocation incorrect");

        increaseAbsoluteCap(idData, type(uint128).max);
        increaseRelativeCap(idData, WAD);

        vm.prank(allocator);
        vault.allocate(adapter, hex"", assets);

        assertEq(underlyingToken.balanceOf(adapter), assets, "Adapter balance incorrect after allocation");
        assertEq(vault.allocation(id), assets, "Allocation incorrect after allocation");
        assertEq(vault.totalAllocation(), assets, "Total allocation incorrect after allocation");
    }

    function testRealizeFunctionProfit(uint256 assets, uint256 profit) public {
        assets = bound(assets, 1, type(uint128).max);
        profit = bound(profit, 0, type(uint128).max - assets);

        setupRealization(assets);

        MockAdapter(adapter).setProfit(profit);

        vm.expectEmit();
        emit EventsLib.Realize(realizer, adapter, ids, int256(profit), 0, 0);
        vm.prank(realizer);
        vault.realize(adapter, hex"");

        assertEq(vault.balanceOf(realizer), 0, "Realizer incorrectly received an incentive");
        assertEq(vault.allocation(id), assets + profit, "Allocation incorrect after realization");
        assertEq(vault.totalAllocation(), assets + profit, "Total allocation incorrect after realization");
    }

    function testRealizeFunctionLoss(uint256 assets, uint256 loss, uint256 lossBuffer) public {
        assets = bound(assets, 1, type(uint128).max / 2);
        loss = bound(loss, 0, assets);
        lossBuffer = bound(lossBuffer, 0, assets);

        setupRealization(assets);

        MockAdapter(adapter).setProfit(lossBuffer);
        vm.prank(allocator);
        vault.allocate(adapter, "", 0);
        assertEq(vault.allocation(id), assets + lossBuffer, "Allocation incorrect after lossBuffer allocation");

        MockAdapter(adapter).setProfit(0);
        MockAdapter(adapter).setLoss(loss);

        uint256 lostAssets = loss > lossBuffer ? loss - lossBuffer : 0;
        uint256 incentive = lostAssets.mulDivDown(LOSS_REALIZATION_INCENTIVE_RATIO, WAD);
        if (incentive > vault.totalAssets() - lostAssets) {
            incentive = vault.totalAssets() - lostAssets;
        }

        uint256 incentiveShares =
            incentive.mulDivDown(vault.totalSupply() + 1, vault.totalAssets() - lostAssets - incentive + 1);

        vm.expectEmit();
        emit EventsLib.Realize(realizer, adapter, ids, -int256(loss), lostAssets, incentiveShares);
        vm.prank(realizer);
        vault.realize(adapter, hex"");

        assertEq(vault.balanceOf(realizer), incentiveShares, "Realizer incentive shares incorrect");
        assertEq(vault.allocation(id), assets + lossBuffer - loss, "Allocation incorrect after realization");
        assertEq(vault.totalAllocation(), assets + lossBuffer - loss, "Total allocation incorrect after realization");
        assertEq(vault.totalAssets(), assets - lostAssets);
    }
}
