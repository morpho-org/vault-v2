// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Morpho Association
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";
import {WhitelistedEntryGate} from "../../src/periphery/WhitelistedEntryGate.sol";
import {
    IWhitelistedEntryGate,
    SET_IS_WHITELISTED_TYPEHASH
} from "../../src/periphery/interfaces/IWhitelistedEntryGate.sol";

contract IntermediaryMock {
    address public initiator;

    function setInitiator(address newInitiator) external {
        initiator = newInitiator;
    }
}

contract WhitelistedEntryGateTest is Test {
    WhitelistedEntryGate internal gate;
    uint256 internal whitelisterPk;
    address internal whitelister;
    address internal alice = makeAddr("alice");
    address internal bob = makeAddr("bob");
    address internal carol = makeAddr("carol");

    function setUp() public {
        whitelisterPk = 0xA11CE;
        whitelister = vm.addr(whitelisterPk);
        gate = new WhitelistedEntryGate(whitelister);
    }

    function _arr(address a) internal pure returns (address[] memory out) {
        out = new address[](1);
        out[0] = a;
    }

    function _arr(address a, address b) internal pure returns (address[] memory out) {
        out = new address[](2);
        out[0] = a;
        out[1] = b;
    }

    function _arr(bool x) internal pure returns (bool[] memory out) {
        out = new bool[](1);
        out[0] = x;
    }

    function _arr(bool x, bool y) internal pure returns (bool[] memory out) {
        out = new bool[](2);
        out[0] = x;
        out[1] = y;
    }

    function _hashAddresses(address[] memory accounts) internal pure returns (bytes32) {
        bytes32[] memory padded = new bytes32[](accounts.length);
        for (uint256 i; i < accounts.length; ++i) padded[i] = bytes32(uint256(uint160(accounts[i])));
        return keccak256(abi.encodePacked(padded));
    }

    function _hashBools(bool[] memory values) internal pure returns (bytes32) {
        bytes32[] memory padded = new bytes32[](values.length);
        for (uint256 i; i < values.length; ++i) padded[i] = bytes32(uint256(values[i] ? 1 : 0));
        return keccak256(abi.encodePacked(padded));
    }

    function _sign(address[] memory accounts, bool[] memory whitelisted, uint256 deadline, uint256 pk)
        internal
        view
        returns (uint8 v, bytes32 r, bytes32 s)
    {
        bytes32 hashStruct = keccak256(
            abi.encode(
                SET_IS_WHITELISTED_TYPEHASH,
                _hashAddresses(accounts),
                _hashBools(whitelisted),
                gate.nonce(),
                deadline
            )
        );
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", gate.DOMAIN_SEPARATOR(), hashStruct));
        return vm.sign(pk, digest);
    }

    function testConstructor() public {
        vm.expectEmit();
        emit IWhitelistedEntryGate.Constructor(whitelister);
        WhitelistedEntryGate g = new WhitelistedEntryGate(whitelister);
        assertEq(g.whitelister(), whitelister);
    }

    function testSetWhitelister() public {
        vm.expectEmit();
        emit IWhitelistedEntryGate.SetWhitelister(bob);
        vm.prank(whitelister);
        gate.setWhitelister(bob);
        assertEq(gate.whitelister(), bob);
    }

    function testSetWhitelisterNotWhitelister() public {
        vm.expectRevert(IWhitelistedEntryGate.NotWhitelister.selector);
        vm.prank(alice);
        gate.setWhitelister(bob);
    }

    function testSetIsWhitelistedSingle() public {
        vm.expectEmit();
        emit IWhitelistedEntryGate.SetIsWhitelisted(alice, true);
        vm.prank(whitelister);
        gate.setIsWhitelisted(_arr(alice), _arr(true));
        assertTrue(gate.isWhitelisted(alice));
    }

    function testSetIsWhitelistedBatch() public {
        vm.expectEmit();
        emit IWhitelistedEntryGate.SetIsWhitelisted(alice, true);
        vm.expectEmit();
        emit IWhitelistedEntryGate.SetIsWhitelisted(bob, false);
        vm.prank(whitelister);
        gate.setIsWhitelisted(_arr(alice, bob), _arr(true, false));
        assertTrue(gate.isWhitelisted(alice));
        assertFalse(gate.isWhitelisted(bob));
    }

    function testSetIsWhitelistedNotWhitelister() public {
        vm.expectRevert(IWhitelistedEntryGate.NotWhitelister.selector);
        vm.prank(alice);
        gate.setIsWhitelisted(_arr(alice), _arr(true));
    }

    function testSetIsWhitelistedLengthMismatch() public {
        vm.expectRevert(IWhitelistedEntryGate.LengthMismatch.selector);
        vm.prank(whitelister);
        gate.setIsWhitelisted(_arr(alice, bob), _arr(true));
    }

    function testSetIsIntermediary() public {
        vm.expectEmit();
        emit IWhitelistedEntryGate.SetIsIntermediary(bob, true);
        vm.prank(whitelister);
        gate.setIsIntermediary(bob, true);
        assertTrue(gate.isIntermediary(bob));
    }

    function testSetIsIntermediaryNotWhitelister() public {
        vm.expectRevert(IWhitelistedEntryGate.NotWhitelister.selector);
        vm.prank(alice);
        gate.setIsIntermediary(bob, true);
    }

    function testEntryGatesDirect() public {
        vm.prank(whitelister);
        gate.setIsWhitelisted(_arr(alice), _arr(true));
        assertTrue(gate.canSendAssets(alice));
        assertTrue(gate.canReceiveShares(alice));
        assertFalse(gate.canSendAssets(bob));
        assertFalse(gate.canReceiveShares(bob));
    }

    function testEntryGatesViaIntermediary() public {
        IntermediaryMock intermediary = new IntermediaryMock();
        intermediary.setInitiator(alice);

        vm.startPrank(whitelister);
        gate.setIsIntermediary(address(intermediary), true);
        gate.setIsWhitelisted(_arr(alice), _arr(true));
        vm.stopPrank();

        assertTrue(gate.canSendAssets(address(intermediary)));
        assertTrue(gate.canReceiveShares(address(intermediary)));

        intermediary.setInitiator(bob);
        assertFalse(gate.canSendAssets(address(intermediary)));
        assertFalse(gate.canReceiveShares(address(intermediary)));
    }

    function testSetIsWhitelistedWithSigSingle() public {
        uint256 deadline = block.timestamp + 1;
        address[] memory accounts = _arr(alice);
        bool[] memory values = _arr(true);
        (uint8 v, bytes32 r, bytes32 s) = _sign(accounts, values, deadline, whitelisterPk);

        vm.expectEmit();
        emit IWhitelistedEntryGate.SetIsWhitelisted(alice, true);
        vm.prank(bob);
        gate.setIsWhitelistedWithSig(accounts, values, deadline, v, r, s);

        assertTrue(gate.isWhitelisted(alice));
        assertEq(gate.nonce(), 1);
    }

    function testSetIsWhitelistedWithSigBatch() public {
        uint256 deadline = block.timestamp + 1;
        address[] memory accounts = _arr(alice, bob);
        bool[] memory values = _arr(true, true);
        (uint8 v, bytes32 r, bytes32 s) = _sign(accounts, values, deadline, whitelisterPk);

        vm.expectEmit();
        emit IWhitelistedEntryGate.SetIsWhitelisted(alice, true);
        vm.expectEmit();
        emit IWhitelistedEntryGate.SetIsWhitelisted(bob, true);
        vm.prank(carol);
        gate.setIsWhitelistedWithSig(accounts, values, deadline, v, r, s);

        assertTrue(gate.isWhitelisted(alice));
        assertTrue(gate.isWhitelisted(bob));
        assertEq(gate.nonce(), 1);
    }

    function testSetIsWhitelistedWithSigDeadlineExpired() public {
        vm.warp(1000);
        uint256 deadline = 1000;
        address[] memory accounts = _arr(alice);
        bool[] memory values = _arr(true);
        (uint8 v, bytes32 r, bytes32 s) = _sign(accounts, values, deadline, whitelisterPk);

        vm.warp(1001);
        vm.expectRevert(IWhitelistedEntryGate.PermitDeadlineExpired.selector);
        gate.setIsWhitelistedWithSig(accounts, values, deadline, v, r, s);
    }

    function testSetIsWhitelistedWithSigInvalidSigner() public {
        uint256 deadline = block.timestamp + 1;
        address[] memory accounts = _arr(alice);
        bool[] memory values = _arr(true);
        (uint8 v, bytes32 r, bytes32 s) = _sign(accounts, values, deadline, 0xBADBAD);

        vm.expectRevert(IWhitelistedEntryGate.InvalidSigner.selector);
        gate.setIsWhitelistedWithSig(accounts, values, deadline, v, r, s);
    }

    function testSetIsWhitelistedWithSigLengthMismatch() public {
        uint256 deadline = block.timestamp + 1;
        address[] memory accounts = _arr(alice, bob);
        bool[] memory values = _arr(true);
        (uint8 v, bytes32 r, bytes32 s) = _sign(accounts, values, deadline, whitelisterPk);

        vm.expectRevert(IWhitelistedEntryGate.LengthMismatch.selector);
        gate.setIsWhitelistedWithSig(accounts, values, deadline, v, r, s);
    }

    function testSetIsWhitelistedWithSigReplayReverts() public {
        uint256 deadline = block.timestamp + 1;
        address[] memory accounts = _arr(alice);
        bool[] memory values = _arr(true);
        (uint8 v, bytes32 r, bytes32 s) = _sign(accounts, values, deadline, whitelisterPk);

        gate.setIsWhitelistedWithSig(accounts, values, deadline, v, r, s);

        vm.expectRevert(IWhitelistedEntryGate.InvalidSigner.selector);
        gate.setIsWhitelistedWithSig(accounts, values, deadline, v, r, s);
    }
}
