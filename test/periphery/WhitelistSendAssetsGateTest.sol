// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Morpho Association
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";
import {WhitelistSendAssetsGate} from "../../src/periphery/WhitelistSendAssetsGate.sol";
import {
    IWhitelistSendAssetsGate,
    SET_IS_WHITELISTED_TYPEHASH
} from "../../src/periphery/interfaces/IWhitelistSendAssetsGate.sol";

contract IntermediaryMock {
    address public initiator;

    function setInitiator(address newInitiator) external {
        initiator = newInitiator;
    }
}

contract WhitelistSendAssetsGateTest is Test {
    WhitelistSendAssetsGate internal gate;
    uint256 internal whitelisterPk;
    address internal whitelister;
    address internal alice = makeAddr("alice");
    address internal bob = makeAddr("bob");

    function setUp() public {
        whitelisterPk = 0xA11CE;
        whitelister = vm.addr(whitelisterPk);
        gate = new WhitelistSendAssetsGate(whitelister);
    }

    function _sign(address account, bool whitelisted, uint256 deadline, uint256 pk)
        internal
        view
        returns (uint8 v, bytes32 r, bytes32 s)
    {
        bytes32 hashStruct = keccak256(
            abi.encode(SET_IS_WHITELISTED_TYPEHASH, account, whitelisted, gate.nonces(account), deadline)
        );
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", gate.DOMAIN_SEPARATOR(), hashStruct));
        return vm.sign(pk, digest);
    }

    function testConstructor() public {
        vm.expectEmit();
        emit IWhitelistSendAssetsGate.Constructor(whitelister);
        WhitelistSendAssetsGate g = new WhitelistSendAssetsGate(whitelister);
        assertEq(g.whitelister(), whitelister);
    }

    function testSetWhitelister() public {
        vm.expectEmit();
        emit IWhitelistSendAssetsGate.SetWhitelister(bob);
        vm.prank(whitelister);
        gate.setWhitelister(bob);
        assertEq(gate.whitelister(), bob);
    }

    function testSetWhitelisterNotWhitelister() public {
        vm.expectRevert(IWhitelistSendAssetsGate.NotWhitelister.selector);
        vm.prank(alice);
        gate.setWhitelister(bob);
    }

    function testSetIsWhitelisted() public {
        vm.expectEmit();
        emit IWhitelistSendAssetsGate.SetIsWhitelisted(alice, true);
        vm.prank(whitelister);
        gate.setIsWhitelisted(alice, true);
        assertTrue(gate.isWhitelisted(alice));
    }

    function testSetIsWhitelistedNotWhitelister() public {
        vm.expectRevert(IWhitelistSendAssetsGate.NotWhitelister.selector);
        vm.prank(alice);
        gate.setIsWhitelisted(alice, true);
    }

    function testSetIsIntermediary() public {
        vm.expectEmit();
        emit IWhitelistSendAssetsGate.SetIsIntermediary(bob, true);
        vm.prank(whitelister);
        gate.setIsIntermediary(bob, true);
        assertTrue(gate.isIntermediary(bob));
    }

    function testSetIsIntermediaryNotWhitelister() public {
        vm.expectRevert(IWhitelistSendAssetsGate.NotWhitelister.selector);
        vm.prank(alice);
        gate.setIsIntermediary(bob, true);
    }

    function testCanSendAssetsDirect() public {
        vm.prank(whitelister);
        gate.setIsWhitelisted(alice, true);
        assertTrue(gate.canSendAssets(alice));
        assertFalse(gate.canSendAssets(bob));
    }

    function testCanSendAssetsViaIntermediary() public {
        IntermediaryMock intermediary = new IntermediaryMock();
        intermediary.setInitiator(alice);

        vm.startPrank(whitelister);
        gate.setIsIntermediary(address(intermediary), true);
        gate.setIsWhitelisted(alice, true);
        vm.stopPrank();

        assertTrue(gate.canSendAssets(address(intermediary)));

        intermediary.setInitiator(bob);
        assertFalse(gate.canSendAssets(address(intermediary)));
    }

    function testSetIsWhitelistedWithSig() public {
        uint256 deadline = block.timestamp + 1;
        (uint8 v, bytes32 r, bytes32 s) = _sign(alice, true, deadline, whitelisterPk);

        vm.expectEmit();
        emit IWhitelistSendAssetsGate.SetIsWhitelisted(alice, true);
        // Relayed by an arbitrary account.
        vm.prank(bob);
        gate.setIsWhitelistedWithSig(alice, true, deadline, v, r, s);

        assertTrue(gate.isWhitelisted(alice));
        assertEq(gate.nonces(alice), 1);
    }

    function testSetIsWhitelistedWithSigDeadlineExpired() public {
        vm.warp(1000);
        uint256 deadline = 1000;
        (uint8 v, bytes32 r, bytes32 s) = _sign(alice, true, deadline, whitelisterPk);

        vm.warp(1001);
        vm.expectRevert(IWhitelistSendAssetsGate.PermitDeadlineExpired.selector);
        gate.setIsWhitelistedWithSig(alice, true, deadline, v, r, s);
    }

    function testSetIsWhitelistedWithSigInvalidSigner() public {
        uint256 deadline = block.timestamp + 1;
        (uint8 v, bytes32 r, bytes32 s) = _sign(alice, true, deadline, 0xBADBAD);

        vm.expectRevert(IWhitelistSendAssetsGate.InvalidSigner.selector);
        gate.setIsWhitelistedWithSig(alice, true, deadline, v, r, s);
    }
}
