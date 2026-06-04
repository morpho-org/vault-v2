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

    function testConstructor(address _whitelister) public {
        vm.expectEmit();
        emit IWhitelistSendAssetsGate.Constructor(_whitelister);
        WhitelistSendAssetsGate g = new WhitelistSendAssetsGate(_whitelister);
        assertEq(g.whitelister(), _whitelister);
    }

    function testSetWhitelister(address newWhitelister) public {
        vm.expectEmit();
        emit IWhitelistSendAssetsGate.SetWhitelister(newWhitelister);
        vm.prank(whitelister);
        gate.setWhitelister(newWhitelister);
        assertEq(gate.whitelister(), newWhitelister);
    }

    function testSetWhitelisterNotWhitelister(address caller, address newWhitelister) public {
        vm.assume(caller != whitelister);
        vm.expectRevert(IWhitelistSendAssetsGate.NotWhitelister.selector);
        vm.prank(caller);
        gate.setWhitelister(newWhitelister);
    }

    function testSetIsWhitelisted(address account, bool whitelisted) public {
        vm.expectEmit();
        emit IWhitelistSendAssetsGate.SetIsWhitelisted(account, whitelisted);
        vm.prank(whitelister);
        gate.setIsWhitelisted(account, whitelisted);
        assertEq(gate.isWhitelisted(account), whitelisted);
    }

    function testSetIsWhitelistedNotWhitelister(address caller, address account, bool whitelisted) public {
        vm.assume(caller != whitelister);
        vm.expectRevert(IWhitelistSendAssetsGate.NotWhitelister.selector);
        vm.prank(caller);
        gate.setIsWhitelisted(account, whitelisted);
    }

    function testSetIsIntermediary(address intermediary, bool isIntermediary_) public {
        vm.expectEmit();
        emit IWhitelistSendAssetsGate.SetIsIntermediary(intermediary, isIntermediary_);
        vm.prank(whitelister);
        gate.setIsIntermediary(intermediary, isIntermediary_);
        assertEq(gate.isIntermediary(intermediary), isIntermediary_);
    }

    function testSetIsIntermediaryNotWhitelister(address caller, address intermediary, bool isIntermediary_) public {
        vm.assume(caller != whitelister);
        vm.expectRevert(IWhitelistSendAssetsGate.NotWhitelister.selector);
        vm.prank(caller);
        gate.setIsIntermediary(intermediary, isIntermediary_);
    }

    function testCanSendAssetsDirect(address account, address other) public {
        vm.assume(account != other);
        vm.prank(whitelister);
        gate.setIsWhitelisted(account, true);
        assertTrue(gate.canSendAssets(account));
        assertFalse(gate.canSendAssets(other));
    }

    function testCanSendAssetsViaIntermediary(address initiator_, address otherInitiator) public {
        vm.assume(initiator_ != otherInitiator);
        IntermediaryMock intermediary = new IntermediaryMock();
        intermediary.setInitiator(initiator_);

        vm.startPrank(whitelister);
        gate.setIsIntermediary(address(intermediary), true);
        gate.setIsWhitelisted(initiator_, true);
        vm.stopPrank();

        assertTrue(gate.canSendAssets(address(intermediary)));

        intermediary.setInitiator(otherInitiator);
        assertFalse(gate.canSendAssets(address(intermediary)));
    }

    function testSetIsWhitelistedWithSig(address account, bool whitelisted, uint256 deadline, address relayer) public {
        deadline = bound(deadline, block.timestamp, type(uint256).max);
        (uint8 v, bytes32 r, bytes32 s) = _sign(account, whitelisted, deadline, whitelisterPk);

        vm.expectEmit();
        emit IWhitelistSendAssetsGate.SetIsWhitelistedWithSig(account, whitelisted);
        // Relayed by an arbitrary account.
        vm.prank(relayer);
        gate.setIsWhitelistedWithSig(account, whitelisted, deadline, v, r, s);

        assertEq(gate.isWhitelisted(account), whitelisted);
        assertEq(gate.nonces(account), 1);
    }

    function testSetIsWhitelistedWithSigDeadlineExpired(
        address account,
        bool whitelisted,
        uint256 deadline,
        uint256 currentTime
    ) public {
        deadline = bound(deadline, 0, type(uint256).max - 1);
        currentTime = bound(currentTime, deadline + 1, type(uint256).max);
        vm.warp(currentTime);
        (uint8 v, bytes32 r, bytes32 s) = _sign(account, whitelisted, deadline, whitelisterPk);

        vm.expectRevert(IWhitelistSendAssetsGate.PermitDeadlineExpired.selector);
        gate.setIsWhitelistedWithSig(account, whitelisted, deadline, v, r, s);
    }

    function testSetIsWhitelistedWithSigInvalidSigner(
        uint256 wrongPk,
        address account,
        bool whitelisted,
        uint256 deadline
    ) public {
        wrongPk = bound(wrongPk, 1, type(uint128).max);
        vm.assume(vm.addr(wrongPk) != whitelister);
        deadline = bound(deadline, block.timestamp, type(uint256).max);
        (uint8 v, bytes32 r, bytes32 s) = _sign(account, whitelisted, deadline, wrongPk);

        vm.expectRevert(IWhitelistSendAssetsGate.InvalidSigner.selector);
        gate.setIsWhitelistedWithSig(account, whitelisted, deadline, v, r, s);
    }

    function testMulticall(address account, address intermediary, bool whitelisted, bool isIntermediary_) public {
        bytes[] memory data = new bytes[](2);
        data[0] = abi.encodeCall(IWhitelistSendAssetsGate.setIsWhitelisted, (account, whitelisted));
        data[1] = abi.encodeCall(IWhitelistSendAssetsGate.setIsIntermediary, (intermediary, isIntermediary_));

        vm.prank(whitelister);
        gate.multicall(data);

        assertEq(gate.isWhitelisted(account), whitelisted);
        assertEq(gate.isIntermediary(intermediary), isIntermediary_);
    }

    function testMulticallBubblesRevert(address caller, address account, bool whitelisted) public {
        vm.assume(caller != whitelister);
        bytes[] memory data = new bytes[](1);
        data[0] = abi.encodeCall(IWhitelistSendAssetsGate.setIsWhitelisted, (account, whitelisted));

        // Called by a non-whitelister: the inner call reverts and the multicall must bubble it up.
        vm.expectRevert(IWhitelistSendAssetsGate.NotWhitelister.selector);
        vm.prank(caller);
        gate.multicall(data);
    }
}
