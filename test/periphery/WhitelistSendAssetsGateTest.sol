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

contract RevertingIntermediaryMock {
    function initiator() external pure returns (address) {
        revert("initiator failed");
    }
}

contract WhitelistSendAssetsGateTest is Test {
    WhitelistSendAssetsGate internal gate;
    uint256 internal whitelisterPk;
    uint256 internal whitelister2Pk;
    address internal roleSetter = makeAddr("roleSetter");
    address internal whitelister;
    address internal whitelister2;
    address internal alice = makeAddr("alice");
    address internal bob = makeAddr("bob");

    function setUp() public {
        whitelisterPk = 0xA11CE;
        whitelister2Pk = 0xB0B;
        whitelister = vm.addr(whitelisterPk);
        whitelister2 = vm.addr(whitelister2Pk);
        gate = new WhitelistSendAssetsGate(roleSetter);
        vm.prank(roleSetter);
        gate.setIsWhitelister(whitelister, true);
    }

    function _sign(address account, bool whitelisted, uint256 deadline, uint256 pk)
        internal
        view
        returns (uint8 v, bytes32 r, bytes32 s)
    {
        bytes32 hashStruct = keccak256(
            abi.encode(
                SET_IS_WHITELISTED_TYPEHASH,
                account,
                whitelisted,
                vm.addr(pk),
                gate.nonces(vm.addr(pk), account),
                deadline
            )
        );
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", gate.DOMAIN_SEPARATOR(), hashStruct));
        return vm.sign(pk, digest);
    }

    function testConstructor(address _roleSetter) public {
        vm.expectEmit();
        emit IWhitelistSendAssetsGate.Constructor(_roleSetter);
        WhitelistSendAssetsGate g = new WhitelistSendAssetsGate(_roleSetter);
        assertEq(g.roleSetter(), _roleSetter);
        assertFalse(g.isWhitelister(_roleSetter));
    }

    function testSetRoleSetter(address newRoleSetter) public {
        vm.expectEmit();
        emit IWhitelistSendAssetsGate.SetRoleSetter(newRoleSetter);
        vm.prank(roleSetter);
        gate.setRoleSetter(newRoleSetter);
        assertEq(gate.roleSetter(), newRoleSetter);
    }

    function testSetRoleSetterNotRoleSetter(address caller, address newRoleSetter) public {
        vm.assume(caller != roleSetter);
        vm.expectRevert(IWhitelistSendAssetsGate.NotRoleSetter.selector);
        vm.prank(caller);
        gate.setRoleSetter(newRoleSetter);
    }

    function testSetIsWhitelister(address account, bool isWhitelister_) public {
        vm.expectEmit();
        emit IWhitelistSendAssetsGate.SetIsWhitelister(account, isWhitelister_);
        vm.prank(roleSetter);
        gate.setIsWhitelister(account, isWhitelister_);
        assertEq(gate.isWhitelister(account), isWhitelister_);
    }

    function testSetIsWhitelisterNotRoleSetter(address caller, address account, bool isWhitelister_) public {
        vm.assume(caller != roleSetter);
        vm.expectRevert(IWhitelistSendAssetsGate.NotRoleSetter.selector);
        vm.prank(caller);
        gate.setIsWhitelister(account, isWhitelister_);
    }

    function testWhitelisterCannotSetIsWhitelister(address account, bool isWhitelister_) public {
        vm.expectRevert(IWhitelistSendAssetsGate.NotRoleSetter.selector);
        vm.prank(whitelister);
        gate.setIsWhitelister(account, isWhitelister_);
    }

    function testMultipleWhitelistersCanSetIsWhitelisted(address account, address account2) public {
        vm.assume(account != account2);

        vm.prank(roleSetter);
        gate.setIsWhitelister(whitelister2, true);

        vm.prank(whitelister);
        gate.setIsWhitelisted(account, true);
        vm.prank(whitelister2);
        gate.setIsWhitelisted(account2, true);

        assertTrue(gate.isWhitelisted(account));
        assertTrue(gate.isWhitelisted(account2));
    }

    function testRevokedWhitelisterCannotSetIsWhitelisted(address account) public {
        vm.prank(roleSetter);
        gate.setIsWhitelister(whitelister, false);

        vm.expectRevert(IWhitelistSendAssetsGate.NotWhitelister.selector);
        vm.prank(whitelister);
        gate.setIsWhitelisted(account, true);
    }

    function testSetIsWhitelisted(address account, bool whitelisted) public {
        vm.expectEmit();
        emit IWhitelistSendAssetsGate.SetIsWhitelisted(whitelister, account, whitelisted);
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
        emit IWhitelistSendAssetsGate.SetIsIntermediary(whitelister, intermediary, isIntermediary_);
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

    function testIntermediaryIgnoresOwnWhitelistUntilDisabled() public {
        IntermediaryMock intermediary = new IntermediaryMock();
        intermediary.setInitiator(bob);

        vm.startPrank(whitelister);
        gate.setIsWhitelisted(address(intermediary), true);
        gate.setIsIntermediary(address(intermediary), true);
        vm.stopPrank();

        assertFalse(gate.canSendAssets(address(intermediary)));

        vm.prank(whitelister);
        gate.setIsIntermediary(address(intermediary), false);

        assertTrue(gate.canSendAssets(address(intermediary)));
    }

    function testIntermediaryInitiatorReverts() public {
        RevertingIntermediaryMock intermediary = new RevertingIntermediaryMock();

        vm.prank(whitelister);
        gate.setIsIntermediary(address(intermediary), true);

        vm.expectRevert("initiator failed");
        gate.canSendAssets(address(intermediary));
    }

    function testSetIsWhitelistedWithSig(address account, bool whitelisted, uint256 deadline, address relayer) public {
        deadline = bound(deadline, block.timestamp, type(uint256).max);
        (uint8 v, bytes32 r, bytes32 s) = _sign(account, whitelisted, deadline, whitelisterPk);

        vm.expectEmit();
        emit IWhitelistSendAssetsGate.SetIsWhitelistedWithSig(whitelister, account, whitelisted);
        // Relayed by an arbitrary account.
        vm.prank(relayer);
        gate.setIsWhitelistedWithSig(whitelister, account, whitelisted, deadline, v, r, s);

        assertEq(gate.isWhitelisted(account), whitelisted);
        assertEq(gate.nonces(whitelister, account), 1);
    }

    function testSetIsWhitelistedWithSigAcceptsAnyWhitelister(
        address account,
        bool whitelisted,
        uint256 deadline,
        address relayer
    ) public {
        deadline = bound(deadline, block.timestamp, type(uint256).max);
        vm.prank(roleSetter);
        gate.setIsWhitelister(whitelister2, true);
        (uint8 v, bytes32 r, bytes32 s) = _sign(account, whitelisted, deadline, whitelister2Pk);

        vm.expectEmit();
        emit IWhitelistSendAssetsGate.SetIsWhitelistedWithSig(whitelister2, account, whitelisted);
        // Relayed by an arbitrary account.
        vm.prank(relayer);
        gate.setIsWhitelistedWithSig(whitelister2, account, whitelisted, deadline, v, r, s);

        assertEq(gate.isWhitelisted(account), whitelisted);
        assertEq(gate.nonces(whitelister2, account), 1);
    }

    function testNoncesArePerWhitelister(address account, uint256 deadline) public {
        deadline = bound(deadline, block.timestamp, type(uint256).max);
        vm.prank(roleSetter);
        gate.setIsWhitelister(whitelister2, true);

        // Both whitelisters sign for the same account at their own nonce 0.
        (uint8 v1, bytes32 r1, bytes32 s1) = _sign(account, true, deadline, whitelisterPk);
        (uint8 v2, bytes32 r2, bytes32 s2) = _sign(account, true, deadline, whitelister2Pk);

        gate.setIsWhitelistedWithSig(whitelister, account, true, deadline, v1, r1, s1);
        gate.setIsWhitelistedWithSig(whitelister2, account, true, deadline, v2, r2, s2);

        assertEq(gate.nonces(whitelister, account), 1);
        assertEq(gate.nonces(whitelister2, account), 1);
    }

    function testSetIsWhitelistedWithSigRejectsRevokedWhitelister(address account, bool whitelisted) public {
        uint256 deadline = block.timestamp + 1 days;
        (uint8 v, bytes32 r, bytes32 s) = _sign(account, whitelisted, deadline, whitelisterPk);

        vm.prank(roleSetter);
        gate.setIsWhitelister(whitelister, false);

        vm.expectRevert(IWhitelistSendAssetsGate.InvalidSigner.selector);
        gate.setIsWhitelistedWithSig(whitelister, account, whitelisted, deadline, v, r, s);
    }

    function testSetIsWhitelistedWithSigRejectsReplayAndTampering() public {
        uint256 deadline = block.timestamp + 1 days;

        (uint8 v, bytes32 r, bytes32 s) = _sign(alice, true, deadline, whitelisterPk);
        gate.setIsWhitelistedWithSig(whitelister, alice, true, deadline, v, r, s);

        // replay
        vm.expectRevert(IWhitelistSendAssetsGate.InvalidSigner.selector);
        gate.setIsWhitelistedWithSig(whitelister, alice, true, deadline, v, r, s);

        // wrong account
        (v, r, s) = _sign(alice, false, deadline, whitelisterPk);
        vm.expectRevert(IWhitelistSendAssetsGate.InvalidSigner.selector);
        gate.setIsWhitelistedWithSig(whitelister, bob, false, deadline, v, r, s);

        // wrong value
        (v, r, s) = _sign(alice, false, deadline, whitelisterPk);
        vm.expectRevert(IWhitelistSendAssetsGate.InvalidSigner.selector);
        gate.setIsWhitelistedWithSig(whitelister, alice, true, deadline, v, r, s);

        // wrong deadline
        (v, r, s) = _sign(alice, false, deadline, whitelisterPk);
        vm.expectRevert(IWhitelistSendAssetsGate.InvalidSigner.selector);
        gate.setIsWhitelistedWithSig(whitelister, alice, false, deadline + 1, v, r, s);

        // wrong whitelister
        (v, r, s) = _sign(alice, false, deadline, whitelisterPk);
        vm.expectRevert(IWhitelistSendAssetsGate.InvalidSigner.selector);
        gate.setIsWhitelistedWithSig(whitelister2, alice, false, deadline, v, r, s);

        // wrong domain separator
        (v, r, s) = _sign(bob, true, deadline, whitelisterPk);
        WhitelistSendAssetsGate otherGate = new WhitelistSendAssetsGate(roleSetter);
        vm.prank(roleSetter);
        otherGate.setIsWhitelister(whitelister, true);
        vm.expectRevert(IWhitelistSendAssetsGate.InvalidSigner.selector);
        otherGate.setIsWhitelistedWithSig(whitelister, bob, true, deadline, v, r, s);
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

        vm.expectRevert(IWhitelistSendAssetsGate.DeadlineExpired.selector);
        gate.setIsWhitelistedWithSig(whitelister, account, whitelisted, deadline, v, r, s);
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
        gate.setIsWhitelistedWithSig(vm.addr(wrongPk), account, whitelisted, deadline, v, r, s);
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
