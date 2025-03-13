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
        vault.submit(abi.encodeWithSelector(IVaultV2.increaseAbsoluteCap.selector, bytes32(bytes20(market)), 1));
        vault.increaseAbsoluteCap(bytes32(bytes20(market)), 1);
        vm.stopPrank();
        deal(address(underlyingToken), supplier, 1);

        vm.startPrank(supplier);
        underlyingToken.approve(address(vault), type(uint256).max);
        vault.deposit(1, supplier);
        vm.stopPrank();
    }
}
