// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Morpho Association
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";
import {WhitelistReceiveSharesGate} from "../../src/periphery/WhitelistReceiveSharesGate.sol";
import {
    IWhitelistReceiveSharesGate,
    SET_IS_WHITELISTED_TYPEHASH
} from "../../src/periphery/interfaces/IWhitelistReceiveSharesGate.sol";

contract WhitelistReceiveSharesGateTest is Test {
    WhitelistReceiveSharesGate internal gate;
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
        gate = new WhitelistReceiveSharesGate(roleSetter);
        vm.prank(roleSetter);
        gate.setIsWhitelister(whitelister, true);
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

    function testConstructor(address _roleSetter) public {
        vm.expectEmit();
        emit IWhitelistReceiveSharesGate.Constructor(_roleSetter);
        WhitelistReceiveSharesGate g = new WhitelistReceiveSharesGate(_roleSetter);
        assertEq(g.roleSetter(), _roleSetter);
        assertFalse(g.isWhitelister(_roleSetter));
    }

    function testSetRoleSetter(address newRoleSetter) public {
        vm.expectEmit();
        emit IWhitelistReceiveSharesGate.SetRoleSetter(newRoleSetter);
        vm.prank(roleSetter);
        gate.setRoleSetter(newRoleSetter);
        assertEq(gate.roleSetter(), newRoleSetter);
    }

    function testSetRoleSetterNotRoleSetter(address caller, address newRoleSetter) public {
        vm.assume(caller != roleSetter);
        vm.expectRevert(IWhitelistReceiveSharesGate.NotRoleSetter.selector);
        vm.prank(caller);
        gate.setRoleSetter(newRoleSetter);
    }

    function testSetIsWhitelister(address account, bool isWhitelister_) public {
        vm.expectEmit();
        emit IWhitelistReceiveSharesGate.SetIsWhitelister(account, isWhitelister_);
        vm.prank(roleSetter);
        gate.setIsWhitelister(account, isWhitelister_);
        assertEq(gate.isWhitelister(account), isWhitelister_);
    }

    function testSetIsWhitelisterNotRoleSetter(address caller, address account, bool isWhitelister_) public {
        vm.assume(caller != roleSetter);
        vm.expectRevert(IWhitelistReceiveSharesGate.NotRoleSetter.selector);
        vm.prank(caller);
        gate.setIsWhitelister(account, isWhitelister_);
    }

    function testWhitelisterCannotSetIsWhitelister(address account, bool isWhitelister_) public {
        vm.expectRevert(IWhitelistReceiveSharesGate.NotRoleSetter.selector);
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

        vm.expectRevert(IWhitelistReceiveSharesGate.NotWhitelister.selector);
        vm.prank(whitelister);
        gate.setIsWhitelisted(account, true);
    }

    function testSetIsWhitelisted(address account, bool whitelisted) public {
        vm.expectEmit();
        emit IWhitelistReceiveSharesGate.SetIsWhitelisted(whitelister, account, whitelisted);
        vm.prank(whitelister);
        gate.setIsWhitelisted(account, whitelisted);
        assertEq(gate.isWhitelisted(account), whitelisted);
    }

    function testSetIsWhitelistedNotWhitelister(address caller, address account, bool whitelisted) public {
        vm.assume(caller != whitelister);
        vm.expectRevert(IWhitelistReceiveSharesGate.NotWhitelister.selector);
        vm.prank(caller);
        gate.setIsWhitelisted(account, whitelisted);
    }

    function testCanReceiveShares(address account, address other) public {
        vm.assume(account != other);
        vm.prank(whitelister);
        gate.setIsWhitelisted(account, true);
        assertTrue(gate.canReceiveShares(account));
        assertFalse(gate.canReceiveShares(other));
    }

    function testSetIsWhitelistedWithSig(address account, bool whitelisted, uint256 deadline, address relayer) public {
        deadline = bound(deadline, block.timestamp, type(uint256).max);
        (uint8 v, bytes32 r, bytes32 s) = _sign(account, whitelisted, deadline, whitelisterPk);

        vm.expectEmit();
        emit IWhitelistReceiveSharesGate.SetIsWhitelistedWithSig(whitelister, account, whitelisted);
        // Relayed by an arbitrary account.
        vm.prank(relayer);
        gate.setIsWhitelistedWithSig(account, whitelisted, deadline, v, r, s);

        assertEq(gate.isWhitelisted(account), whitelisted);
        assertEq(gate.nonces(account), 1);
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
        emit IWhitelistReceiveSharesGate.SetIsWhitelistedWithSig(whitelister2, account, whitelisted);
        // Relayed by an arbitrary account.
        vm.prank(relayer);
        gate.setIsWhitelistedWithSig(account, whitelisted, deadline, v, r, s);

        assertEq(gate.isWhitelisted(account), whitelisted);
        assertEq(gate.nonces(account), 1);
    }

    function testSetIsWhitelistedWithSigRejectsRevokedWhitelister(address account, bool whitelisted) public {
        uint256 deadline = block.timestamp + 1 days;
        (uint8 v, bytes32 r, bytes32 s) = _sign(account, whitelisted, deadline, whitelisterPk);

        vm.prank(roleSetter);
        gate.setIsWhitelister(whitelister, false);

        vm.expectRevert(IWhitelistReceiveSharesGate.InvalidSigner.selector);
        gate.setIsWhitelistedWithSig(account, whitelisted, deadline, v, r, s);
    }

    function testSetIsWhitelistedWithSigRejectsReplayAndTampering() public {
        uint256 deadline = block.timestamp + 1 days;

        (uint8 v, bytes32 r, bytes32 s) = _sign(alice, true, deadline, whitelisterPk);
        gate.setIsWhitelistedWithSig(alice, true, deadline, v, r, s);

        // replay
        vm.expectRevert(IWhitelistReceiveSharesGate.InvalidSigner.selector);
        gate.setIsWhitelistedWithSig(alice, true, deadline, v, r, s);

        // wrong account
        (v, r, s) = _sign(alice, false, deadline, whitelisterPk);
        vm.expectRevert(IWhitelistReceiveSharesGate.InvalidSigner.selector);
        gate.setIsWhitelistedWithSig(bob, false, deadline, v, r, s);

        // wrong value
        (v, r, s) = _sign(alice, false, deadline, whitelisterPk);
        vm.expectRevert(IWhitelistReceiveSharesGate.InvalidSigner.selector);
        gate.setIsWhitelistedWithSig(alice, true, deadline, v, r, s);

        // wrong deadline
        (v, r, s) = _sign(alice, false, deadline, whitelisterPk);
        vm.expectRevert(IWhitelistReceiveSharesGate.InvalidSigner.selector);
        gate.setIsWhitelistedWithSig(alice, false, deadline + 1, v, r, s);

        // wrong domain separator
        (v, r, s) = _sign(bob, true, deadline, whitelisterPk);
        WhitelistReceiveSharesGate otherGate = new WhitelistReceiveSharesGate(roleSetter);
        vm.prank(roleSetter);
        otherGate.setIsWhitelister(whitelister, true);
        vm.expectRevert(IWhitelistReceiveSharesGate.InvalidSigner.selector);
        otherGate.setIsWhitelistedWithSig(bob, true, deadline, v, r, s);
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

        vm.expectRevert(IWhitelistReceiveSharesGate.DeadlineExpired.selector);
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

        vm.expectRevert(IWhitelistReceiveSharesGate.InvalidSigner.selector);
        gate.setIsWhitelistedWithSig(account, whitelisted, deadline, v, r, s);
    }

    function testMulticall(address account, bool whitelisted, address account2, bool whitelisted2) public {
        bytes[] memory data = new bytes[](2);
        data[0] = abi.encodeCall(IWhitelistReceiveSharesGate.setIsWhitelisted, (account, whitelisted));
        data[1] = abi.encodeCall(IWhitelistReceiveSharesGate.setIsWhitelisted, (account2, whitelisted2));

        vm.prank(whitelister);
        gate.multicall(data);

        if (account == account2) {
            assertEq(gate.isWhitelisted(account), whitelisted2);
        } else {
            assertEq(gate.isWhitelisted(account), whitelisted);
            assertEq(gate.isWhitelisted(account2), whitelisted2);
        }
    }

    function testMulticallBubblesRevert(address caller, address account, bool whitelisted) public {
        vm.assume(caller != whitelister);
        bytes[] memory data = new bytes[](1);
        data[0] = abi.encodeCall(IWhitelistReceiveSharesGate.setIsWhitelisted, (account, whitelisted));

        // Called by a non-whitelister: the inner call reverts and the multicall must bubble it up.
        vm.expectRevert(IWhitelistReceiveSharesGate.NotWhitelister.selector);
        vm.prank(caller);
        gate.multicall(data);
    }
}
