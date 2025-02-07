// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import {BaseTest, VaultsV2, EncodeLib} from "./BaseTest.sol";
import {ERC4626Mock} from "./mocks/ERC4626Mock.sol";

contract ManagedVaultTest is BaseTest {
    address public immutable supplier = makeAddr("supplier");

    function setUp() public override {
        super.setUp();

        ERC4626Mock market = new ERC4626Mock(underlyingToken, "LendingMarket", "MKT");
        vm.prank(curator);
        vault.newMarket(address(market));
        deal(address(underlyingToken), supplier, 1);

        vm.startPrank(supplier);
        underlyingToken.approve(address(vault), type(uint256).max);
        vault.deposit(1, supplier);
        vm.stopPrank();
    }

    function testRevertNonManager(address caller) public {
        vm.assume(caller != manager);
        bundle.push(EncodeLib.reallocateFromIdleCall({marketIndex: 0, amount: 1}));
        vm.prank(caller);
        vm.expectRevert();
        vault.multiCall(bundle);
    }

    function testManager() public {
        bundle.push(EncodeLib.reallocateFromIdleCall({marketIndex: 0, amount: 1}));
        vm.prank(manager);
        vault.multiCall(bundle);
    }
}
