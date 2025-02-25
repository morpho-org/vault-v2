// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import "./BaseTest.sol";

import {ERC4626Mock} from "./mocks/ERC4626Mock.sol";

contract ManagedVaultTest is BaseTest {
    address public immutable supplier = makeAddr("supplier");
    address public market;

    function setUp() public override {
        super.setUp();

        market = address(new ERC4626Mock(underlyingToken, "LendingMarket", "MKT"));
        vm.label(market, "market");
        vm.startPrank(curator);
        vault.submitCapUnzero(market, 1);
        vault.accept(uint256(keccak256(abi.encode(market, 12))));
        vm.stopPrank();
        deal(address(underlyingToken), supplier, 1);

        vm.startPrank(supplier);
        underlyingToken.approve(address(vault), type(uint256).max);
        vault.deposit(1, supplier);
        vm.stopPrank();
    }

    function testRevertNonManager(address caller) public {
        vm.assume(caller != manager);
        bundle.push(EncodeLib.reallocateFromIdleCall({market: market, amount: 1}));
        vm.prank(caller);
        vm.expectRevert();
        vault.multicall(bundle);
    }

    function testManager() public {
        bundle.push(EncodeLib.reallocateFromIdleCall({market: market, amount: 1}));
        vm.prank(manager);
        vault.multicall(bundle);
    }
}
