// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Morpho Association
pragma solidity ^0.8.0;

import {Test} from "../../lib/forge-std/src/Test.sol";
import {
    MidnightAdapterLossRealizationFunder
} from "../../src/periphery/midnight-adapter-loss-realization-funder/MidnightAdapterLossRealizationFunder.sol";
import {
    IMidnightAdapterLossRealizationFunder
} from "../../src/periphery/midnight-adapter-loss-realization-funder/interfaces/IMidnightAdapterLossRealizationFunder.sol";
import {Market} from "../../lib/midnight/src/interfaces/IMidnight.sol";
import {IdLib} from "../../lib/midnight/src/libraries/IdLib.sol";

contract LossRealizationAdapterMock {
    address public parentVault;
    address public asset = address(1);
    uint256 public realAssets = 100e18;
    mapping(bytes32 marketId => uint256) public pendingLoss;
    mapping(bytes32 marketId => uint256) public calls;

    constructor(address _parentVault) {
        parentVault = _parentVault;
    }

    function setLoss(Market memory market, uint256 loss) external {
        pendingLoss[IdLib.toId(market)] = loss;
    }

    function withdrawToVault(Market memory market, uint256 assets) external {
        require(assets == 0, "Nonzero withdrawal");
        bytes32 marketId = IdLib.toId(market);
        realAssets -= pendingLoss[marketId];
        delete pendingLoss[marketId];
        calls[marketId]++;
    }
}

contract LossRealizationReceiver {
    bool public rejects;
    uint256 public calls;
    address public target;
    bytes public callback;
    bool public callbackSuccess;
    bytes public callbackReturnData;

    function setRejects(bool newRejects) external {
        rejects = newRejects;
    }

    function setCallback(address newTarget, bytes memory newCallback) external {
        target = newTarget;
        callback = newCallback;
    }

    receive() external payable {
        require(!rejects, "Rejected");
        calls++;
        if (callback.length > 0) {
            bytes memory data = callback;
            delete callback;
            (callbackSuccess, callbackReturnData) = target.call(data);
        }
    }
}

contract MidnightAdapterLossRealizationFunderTest is Test {
    MidnightAdapterLossRealizationFunder internal funder;
    LossRealizationAdapterMock internal adapter;
    LossRealizationReceiver internal contractReceiver;
    address internal owner = makeAddr("owner");
    address internal caller = makeAddr("caller");
    address internal receiver = makeAddr("receiver");
    address internal parentVault = makeAddr("parentVault");
    Market[] internal markets;

    function setUp() public {
        adapter = new LossRealizationAdapterMock(parentVault);
        funder = new MidnightAdapterLossRealizationFunder(address(adapter), owner);
        contractReceiver = new LossRealizationReceiver();
        deal(address(funder), 1 ether);
        vm.startPrank(owner);
        funder.setIncentive(0.01 ether);
        funder.setMinimumLossBeforeIncentive(1e18);
        vm.stopPrank();
        markets.push();
        markets[0].loanToken = adapter.asset();
        markets[0].maturity = 7 days;
        markets.push();
        markets[1].loanToken = adapter.asset();
        markets[1].maturity = 30 days;
    }

    function testConstructor(address newOwner, uint96 assets) public {
        deal(address(this), assets);
        vm.expectEmit();
        emit IMidnightAdapterLossRealizationFunder.Constructor(address(adapter), newOwner);
        MidnightAdapterLossRealizationFunder deployed =
            new MidnightAdapterLossRealizationFunder{value: assets}(address(adapter), newOwner);

        assertEq(deployed.adapter(), address(adapter));
        assertEq(deployed.parentVault(), parentVault);
        assertEq(deployed.owner(), newOwner);
        assertEq(deployed.incentive(), 0);
        assertEq(deployed.minimumLossBeforeIncentive(), 0);
        assertEq(address(deployed).balance, assets);
    }

    function testReceive(uint96 assets) public {
        deal(address(this), assets);
        (bool success,) = address(funder).call{value: assets}("");
        assertTrue(success);
        assertEq(address(funder).balance, 1 ether + uint256(assets));
    }

    function testSetOwner(address newOwner) public {
        vm.expectEmit(address(funder));
        emit IMidnightAdapterLossRealizationFunder.SetOwner(newOwner);
        vm.prank(owner);
        funder.setOwner(newOwner);
        assertEq(funder.owner(), newOwner);
    }

    function testOwnershipTransfer() public {
        vm.prank(owner);
        funder.setOwner(caller);
        vm.expectRevert(IMidnightAdapterLossRealizationFunder.NotOwner.selector);
        vm.prank(owner);
        funder.setIncentive(1);
        vm.prank(caller);
        funder.setIncentive(1);
        assertEq(funder.incentive(), 1);
    }

    function testSetIncentive(uint256 newIncentive) public {
        vm.expectEmit(address(funder));
        emit IMidnightAdapterLossRealizationFunder.SetIncentive(newIncentive);
        vm.prank(owner);
        funder.setIncentive(newIncentive);
        assertEq(funder.incentive(), newIncentive);
        assertEq(funder.minimumLossBeforeIncentive(), 1e18);
    }

    function testSetMinimumLossBeforeIncentive(uint256 newMinimumLossBeforeIncentive) public {
        vm.expectEmit(address(funder));
        emit IMidnightAdapterLossRealizationFunder.SetMinimumLossBeforeIncentive(newMinimumLossBeforeIncentive);
        vm.prank(owner);
        funder.setMinimumLossBeforeIncentive(newMinimumLossBeforeIncentive);
        assertEq(funder.minimumLossBeforeIncentive(), newMinimumLossBeforeIncentive);
        assertEq(funder.incentive(), 0.01 ether);
    }

    function testOwnerFunctionsUnauthorized(address nonOwner) public {
        vm.assume(nonOwner != owner);
        vm.startPrank(nonOwner);
        vm.expectRevert(IMidnightAdapterLossRealizationFunder.NotOwner.selector);
        funder.setOwner(nonOwner);
        vm.expectRevert(IMidnightAdapterLossRealizationFunder.NotOwner.selector);
        funder.setIncentive(0);
        vm.expectRevert(IMidnightAdapterLossRealizationFunder.NotOwner.selector);
        funder.setMinimumLossBeforeIncentive(0);
        vm.expectRevert(IMidnightAdapterLossRealizationFunder.NotOwner.selector);
        funder.withdraw(0, payable(nonOwner));
        vm.stopPrank();
    }

    function testWithdraw(uint256 assets) public {
        assets = bound(assets, 0, 1 ether);
        vm.expectEmit(address(funder));
        emit IMidnightAdapterLossRealizationFunder.WithdrawEth(receiver, assets);
        vm.prank(owner);
        funder.withdraw(assets, payable(receiver));
        assertEq(receiver.balance, assets);
        assertEq(address(funder).balance, 1 ether - assets);
    }

    function testWithdrawInsufficientBalance() public {
        vm.expectRevert(IMidnightAdapterLossRealizationFunder.EthTransferFailed.selector);
        vm.prank(owner);
        funder.withdraw(1 ether + 1, payable(receiver));
        assertEq(address(funder).balance, 1 ether);
        assertEq(receiver.balance, 0);
    }

    function testWithdrawRejectingReceiver() public {
        contractReceiver.setRejects(true);
        vm.expectRevert(IMidnightAdapterLossRealizationFunder.EthTransferFailed.selector);
        vm.prank(owner);
        funder.withdraw(1 ether, payable(address(contractReceiver)));
        assertEq(address(funder).balance, 1 ether);
    }

    function testRealizeLossThreshold(uint256 pendingLoss, uint256 minimumLoss) public {
        pendingLoss = bound(pendingLoss, 0, 2e18);
        minimumLoss = bound(minimumLoss, 0, 2e18);
        adapter.setLoss(markets[0], pendingLoss);
        vm.prank(owner);
        funder.setMinimumLossBeforeIncentive(minimumLoss);
        uint256 expectedPaid = pendingLoss > 0 && minimumLoss > 0 && pendingLoss >= minimumLoss ? 0.01 ether : 0;

        vm.expectEmit(address(funder));
        emit IMidnightAdapterLossRealizationFunder.RealizeLoss(caller, marketIds(), pendingLoss, expectedPaid, receiver);
        vm.prank(caller);
        (uint256 loss, uint256 paid) = funder.realizeLoss(markets, payable(receiver));

        assertEq(loss, pendingLoss);
        assertEq(paid, expectedPaid);
        assertEq(receiver.balance, expectedPaid);
        assertEq(caller.balance, 0);
        assertEq(address(funder).balance, 1 ether - expectedPaid);
        assertEq(adapter.realAssets(), 100e18 - pendingLoss);
        assertEq(adapter.pendingLoss(IdLib.toId(markets[0])), 0);
        assertEq(adapter.calls(IdLib.toId(markets[0])), 1);
        assertEq(adapter.calls(IdLib.toId(markets[1])), 1);
    }

    function testRealizeLossExactlyAtThreshold() public {
        adapter.setLoss(markets[0], 1e18);
        (uint256 loss, uint256 paid) = funder.realizeLoss(markets, payable(receiver));
        assertEq(loss, 1e18);
        assertEq(paid, 0.01 ether);
    }

    function testRealizeLossBelowThresholdDoesNotCallReceiver() public {
        adapter.setLoss(markets[0], 1e18 - 1);
        contractReceiver.setRejects(true);
        (uint256 loss, uint256 paid) = funder.realizeLoss(markets, payable(address(contractReceiver)));
        assertEq(loss, 1e18 - 1);
        assertEq(paid, 0);
        assertEq(adapter.realAssets(), 99e18 + 1);
        assertEq(contractReceiver.calls(), 0);
    }

    function testRealizeLossBatchAggregatesSmallLosses() public {
        adapter.setLoss(markets[0], 0.4e18);
        adapter.setLoss(markets[1], 0.6e18);
        (uint256 loss, uint256 paid) = funder.realizeLoss(markets, payable(receiver));
        assertEq(loss, 1e18);
        assertEq(paid, 0.01 ether);
        assertEq(receiver.balance, 0.01 ether);
    }

    function testRealizeLossBatchPaysOnce() public {
        adapter.setLoss(markets[0], 1e18);
        adapter.setLoss(markets[1], 2e18);
        (uint256 loss, uint256 paid) = funder.realizeLoss(markets, payable(receiver));
        assertEq(loss, 3e18);
        assertEq(paid, 0.01 ether);
        assertEq(receiver.balance, 0.01 ether);
    }

    function testRealizeLossRepeatedPositionCountedOnce() public {
        adapter.setLoss(markets[0], 1e18);
        Market[] memory repeated = new Market[](2);
        repeated[0] = markets[0];
        repeated[1] = markets[0];
        (uint256 loss, uint256 paid) = funder.realizeLoss(repeated, payable(receiver));
        assertEq(loss, 1e18);
        assertEq(paid, 0.01 ether);
        assertEq(adapter.calls(IdLib.toId(markets[0])), 2);
    }

    function testRealizeLossRepeatedCallDoesNotPayAgain() public {
        adapter.setLoss(markets[0], 1e18);
        funder.realizeLoss(markets, payable(receiver));
        (uint256 loss, uint256 paid) = funder.realizeLoss(markets, payable(receiver));
        assertEq(loss, 0);
        assertEq(paid, 0);
        assertEq(receiver.balance, 0.01 ether);
    }

    function testRealizeLossEmptyBatch() public {
        (uint256 loss, uint256 paid) = funder.realizeLoss(new Market[](0), payable(receiver));
        assertEq(loss, 0);
        assertEq(paid, 0);
        assertEq(receiver.balance, 0);
    }

    function testZeroThresholdDoesNotPayForEmptyBatch() public {
        vm.prank(owner);
        funder.setMinimumLossBeforeIncentive(0);
        (uint256 loss, uint256 paid) = funder.realizeLoss(new Market[](0), payable(receiver));
        assertEq(loss, 0);
        assertEq(paid, 0);
        assertEq(receiver.balance, 0);
    }

    function testZeroThresholdDoesNotPayForPositiveLoss() public {
        vm.prank(owner);
        funder.setMinimumLossBeforeIncentive(0);
        adapter.setLoss(markets[0], 1e18);
        contractReceiver.setRejects(true);
        (uint256 loss, uint256 paid) = funder.realizeLoss(markets, payable(address(contractReceiver)));
        assertEq(loss, 1e18);
        assertEq(paid, 0);
        assertEq(adapter.realAssets(), 99e18);
        assertEq(contractReceiver.calls(), 0);
        assertEq(address(funder).balance, 1 ether);
    }

    function testZeroIncentiveStillCallsReceiver() public {
        vm.prank(owner);
        funder.setIncentive(0);
        adapter.setLoss(markets[0], 1e18);
        (uint256 loss, uint256 paid) = funder.realizeLoss(markets, payable(address(contractReceiver)));
        assertEq(loss, 1e18);
        assertEq(paid, 0);
        assertEq(contractReceiver.calls(), 1);
    }

    function testRealizeLossRejectingReceiverRollsBack() public {
        adapter.setLoss(markets[0], 1e18);
        contractReceiver.setRejects(true);
        vm.expectRevert(IMidnightAdapterLossRealizationFunder.EthTransferFailed.selector);
        funder.realizeLoss(markets, payable(address(contractReceiver)));
        assertEq(adapter.realAssets(), 100e18);
        assertEq(adapter.pendingLoss(IdLib.toId(markets[0])), 1e18);
        assertEq(adapter.calls(IdLib.toId(markets[0])), 0);
        assertEq(address(funder).balance, 1 ether);
    }

    function testRealizeLossInsufficientBalanceRollsBack() public {
        adapter.setLoss(markets[0], 1e18);
        deal(address(funder), 0.01 ether - 1);
        vm.expectRevert(IMidnightAdapterLossRealizationFunder.EthTransferFailed.selector);
        funder.realizeLoss(markets, payable(receiver));
        assertEq(adapter.realAssets(), 100e18);
        assertEq(adapter.pendingLoss(IdLib.toId(markets[0])), 1e18);
        assertEq(address(funder).balance, 0.01 ether - 1);
        assertEq(receiver.balance, 0);
    }

    function testRealizeLossAdapterRevertRollsBackBatch() public {
        adapter.setLoss(markets[0], 1e18);
        vm.mockCallRevert(
            address(adapter), abi.encodeCall(LossRealizationAdapterMock.withdrawToVault, (markets[1], 0)), "Failed"
        );
        vm.expectRevert(bytes("Failed"));
        funder.realizeLoss(markets, payable(receiver));
        assertEq(adapter.realAssets(), 100e18);
        assertEq(adapter.pendingLoss(IdLib.toId(markets[0])), 1e18);
        assertEq(receiver.balance, 0);
    }

    function testReceiverReentryCannotRewardSameLossTwice() public {
        adapter.setLoss(markets[0], 1e18);
        contractReceiver.setCallback(
            address(funder),
            abi.encodeCall(IMidnightAdapterLossRealizationFunder.realizeLoss, (markets, payable(receiver)))
        );
        (uint256 loss, uint256 paid) = funder.realizeLoss(markets, payable(address(contractReceiver)));
        assertEq(loss, 1e18);
        assertEq(paid, 0.01 ether);
        assertTrue(contractReceiver.callbackSuccess());
        (uint256 nestedLoss, uint256 nestedPaid) = abi.decode(contractReceiver.callbackReturnData(), (uint256, uint256));
        assertEq(nestedLoss, 0);
        assertEq(nestedPaid, 0);
        assertEq(receiver.balance, 0);
        assertEq(address(contractReceiver).balance, 0.01 ether);
        assertEq(address(funder).balance, 0.99 ether);
    }

    function testReceiverReentryCanRewardDifferentLoss() public {
        adapter.setLoss(markets[0], 1e18);
        adapter.setLoss(markets[1], 1e18);
        Market[] memory outerMarkets = new Market[](1);
        outerMarkets[0] = markets[0];
        Market[] memory nestedMarkets = new Market[](1);
        nestedMarkets[0] = markets[1];
        contractReceiver.setCallback(
            address(funder),
            abi.encodeCall(IMidnightAdapterLossRealizationFunder.realizeLoss, (nestedMarkets, payable(receiver)))
        );
        (uint256 loss, uint256 paid) = funder.realizeLoss(outerMarkets, payable(address(contractReceiver)));
        assertEq(loss, 1e18);
        assertEq(paid, 0.01 ether);
        assertTrue(contractReceiver.callbackSuccess());
        (uint256 nestedLoss, uint256 nestedPaid) = abi.decode(contractReceiver.callbackReturnData(), (uint256, uint256));
        assertEq(nestedLoss, 1e18);
        assertEq(nestedPaid, 0.01 ether);
        assertEq(adapter.realAssets(), 98e18);
        assertEq(receiver.balance, 0.01 ether);
        assertEq(address(contractReceiver).balance, 0.01 ether);
        assertEq(address(funder).balance, 0.98 ether);
    }

    function testReceiverChangingIncentiveDoesNotChangePaid() public {
        adapter.setLoss(markets[0], 1e18);
        vm.prank(owner);
        funder.setOwner(address(contractReceiver));
        contractReceiver.setCallback(
            address(funder), abi.encodeCall(IMidnightAdapterLossRealizationFunder.setIncentive, (1 ether))
        );
        vm.expectEmit(address(funder));
        emit IMidnightAdapterLossRealizationFunder.RealizeLoss(
            address(this), marketIds(), 1e18, 0.01 ether, address(contractReceiver)
        );
        (uint256 loss, uint256 paid) = funder.realizeLoss(markets, payable(address(contractReceiver)));
        assertEq(loss, 1e18);
        assertEq(paid, 0.01 ether);
        assertTrue(contractReceiver.callbackSuccess());
        assertEq(funder.incentive(), 1 ether);
        assertEq(address(contractReceiver).balance, 0.01 ether);
    }

    function marketIds() internal view returns (bytes32[] memory ids) {
        ids = new bytes32[](markets.length);
        for (uint256 i = 0; i < markets.length; i++) {
            ids[i] = IdLib.toId(markets[i]);
        }
    }
}
