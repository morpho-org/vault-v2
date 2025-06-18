// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Morpho Association
pragma solidity ^0.8.0;

import "./BaseTest.sol";
import "./examples/GateExample.sol";

contract Bundler3Mock {
    address private _initiator;

    constructor(address initiator_) {
        _initiator = initiator_;
    }

    function initiator() external view returns (address) {
        return _initiator;
    }
}

contract BundlerAdapterMock {
    IBundler3 private _bundler3;

    constructor(IBundler3 bundler3_) {
        _bundler3 = bundler3_;
    }

    function BUNDLER3() external view returns (IBundler3) {
        return _bundler3;
    }
}

contract GateExampleTest is BaseTest {
    GateExample gate;
    address gateOwner;

    function setUp() public override {
        super.setUp();

        gateOwner = makeAddr("gateOwner");

        gate = new GateExample(gateOwner);
    }

    function testConstructor() public view {
        assertEq(gate.owner(), gateOwner);
    }

    function testOwnerOperations(address newOwner, address nonOwner) public {
        vm.assume(newOwner != address(0));
        vm.assume(nonOwner != address(0) && nonOwner != gateOwner);

        // Non-owner cannot set owner
        vm.prank(nonOwner);
        vm.expectRevert(GateExample.Unauthorized.selector);
        gate.setOwner(newOwner);

        // Owner can set owner
        vm.prank(gateOwner);
        gate.setOwner(newOwner);
        assertEq(gate.owner(), newOwner);
    }

    function testWhitelistOperations(address account, bool isWhitelisted, address nonOwner) public {
        vm.assume(account != address(0));
        vm.assume(nonOwner != address(0) && nonOwner != gateOwner);

        // Non-owner cannot whitelist
        vm.prank(nonOwner);
        vm.expectRevert(GateExample.Unauthorized.selector);
        gate.setIsWhitelisted(account, isWhitelisted);

        // Owner can whitelist
        vm.prank(gateOwner);
        gate.setIsWhitelisted(account, isWhitelisted);
        assertEq(gate.whitelisted(account), isWhitelisted);

        // Check that permission functions match whitelist status
        assertEq(gate.canSendShares(account), isWhitelisted);
        assertEq(gate.canReceiveAssets(account), isWhitelisted);
        assertEq(gate.canReceiveShares(account), isWhitelisted);
        assertEq(gate.canSendAssets(account), isWhitelisted);
    }

    function testBundlerAdapterOperations(address adapterAddr, bool isAdapter, address nonOwner) public {
        vm.assume(adapterAddr != address(0));
        vm.assume(nonOwner != address(0) && nonOwner != gateOwner);

        // Non-owner cannot set bundler adapter
        vm.prank(nonOwner);
        vm.expectRevert(GateExample.Unauthorized.selector);
        gate.setIsBundlerAdapter(adapterAddr, isAdapter);

        // Owner can set bundler adapter
        vm.prank(gateOwner);
        gate.setIsBundlerAdapter(adapterAddr, isAdapter);
        assertEq(gate.isBundlerAdapter(adapterAddr), isAdapter);
    }

    function testAdapterWithWhitelistedInitiator(address initiatorAddr, bool isWhitelisted) public {
        vm.assume(initiatorAddr != address(0));

        // Create a new bundler and adapter for the test
        address bundlerAddr = address(new Bundler3Mock(initiatorAddr));
        address adapterAddr = address(new BundlerAdapterMock(IBundler3(bundlerAddr)));

        // Test when adapter is not registered
        vm.prank(gateOwner);
        gate.setIsWhitelisted(initiatorAddr, isWhitelisted);

        assertFalse(gate.canSendShares(adapterAddr));
        assertFalse(gate.canReceiveAssets(adapterAddr));
        assertFalse(gate.canReceiveShares(adapterAddr));
        assertFalse(gate.canSendAssets(adapterAddr));

        // Test when adapter is registered
        vm.prank(gateOwner);
        gate.setIsBundlerAdapter(adapterAddr, true);

        assertEq(gate.canSendShares(adapterAddr), isWhitelisted);
        assertEq(gate.canReceiveAssets(adapterAddr), isWhitelisted);
        assertEq(gate.canReceiveShares(adapterAddr), isWhitelisted);
        assertEq(gate.canSendAssets(adapterAddr), isWhitelisted);
    }
}
