// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Morpho Association
pragma solidity ^0.8.0;

import "./BaseTest.sol";
import "../src/libraries/EventsLib.sol";
import {DOMAIN_TYPEHASH, PERMIT_TYPEHASH} from "../src/libraries/ConstantsLib.sol";
import {stdStorage, StdStorage} from "../lib/forge-std/src/Test.sol";

contract ERC20Test is BaseTest {
    using stdStorage for StdStorage;

    uint256 constant MAX_TEST_SHARES = 1e36;

    struct PermitInfo {
        uint256 privateKey;
        uint256 nonce;
        uint256 deadline;
    }

    function _signPermit(uint256 privateKey, address owner, address to, uint256 shares, uint256 nonce, uint256 deadline)
        internal
        view
        returns (uint8, bytes32, bytes32)
    {
        bytes32 hashStruct = keccak256(abi.encode(PERMIT_TYPEHASH, owner, to, shares, nonce, deadline));
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", vault.DOMAIN_SEPARATOR(), hashStruct));
        return vm.sign(privateKey, digest);
    }

    function _setupPermit(PermitInfo calldata p)
        internal
        view
        returns (address owner, uint256 privateKey, uint256 nonce, uint256 deadline)
    {
        privateKey = boundPrivateKey(p.privateKey);
        owner = vm.addr(privateKey);
        deadline = bound(p.deadline, block.timestamp, type(uint256).max);
        nonce = bound(p.nonce, 0, type(uint256).max - 1);
    }

    function _setCurrentNonce(address owner, uint256 nonce) internal {
        stdstore.target(address(vault)).sig("nonces(address)").with_key(owner).checked_write(nonce);
    }

    function setUp() public override {
        super.setUp();

        deal(address(underlyingToken), address(this), type(uint256).max);
        underlyingToken.approve(address(vault), type(uint256).max);
    }

    function testCreateShares(uint256 shares) public {
        vm.assume(shares <= MAX_TEST_SHARES);

        vm.expectEmit();
        emit EventsLib.Transfer(address(0), address(this), shares);

        vault.mint(shares, address(this));
        assertEq(vault.totalSupply(), shares, "total supply");
        assertEq(vault.balanceOf(address(this)), shares, "balance");
    }

    function testCreateSharesZeroAddress(uint256 shares) public {
        vm.assume(shares <= type(uint256).max / vault.virtualShares());
        vm.expectRevert(ErrorsLib.ZeroAddress.selector);
        vault.mint(shares, address(0));
    }

    function testDeleteShares(uint256 shares, uint256 sharesRedeemed) public {
        vm.assume(shares <= MAX_TEST_SHARES);
        sharesRedeemed = bound(sharesRedeemed, 0, shares);

        vault.mint(shares, address(this));
        vm.expectEmit();
        emit EventsLib.Transfer(address(this), address(0), sharesRedeemed);

        vault.redeem(sharesRedeemed, address(this), address(this));

        assertEq(vault.totalSupply(), shares - sharesRedeemed, "total supply");
        assertEq(vault.balanceOf(address(this)), shares - sharesRedeemed, "balance");
    }

    function testDeleteSharesZeroAddress() public {
        vm.expectRevert(ErrorsLib.ZeroAddress.selector);
        vault.redeem(0, address(this), address(0));
    }

    function testApprove(address spender, uint256 shares) public {
        vm.assume(shares <= MAX_TEST_SHARES);
        vm.expectEmit();
        emit EventsLib.Approval(address(this), address(spender), shares);

        assertTrue(vault.approve(spender, shares));
        assertEq(vault.allowance(address(this), spender), shares);
    }

    function testTransfer(address to, uint256 shares, uint256 sharesTransferred) public {
        vm.assume(shares <= MAX_TEST_SHARES);
        vm.assume(to != address(0));
        sharesTransferred = bound(sharesTransferred, 0, shares);

        vault.mint(shares, address(this));

        vm.expectEmit();
        emit EventsLib.Transfer(address(this), address(to), sharesTransferred);

        assertTrue(vault.transfer(to, sharesTransferred));

        assertEq(vault.totalSupply(), shares, "total supply");
        if (address(this) == to) {
            assertEq(vault.balanceOf(address(this)), shares, "balance");
        } else {
            assertEq(vault.balanceOf(address(this)), shares - sharesTransferred, "balance from");
            assertEq(vault.balanceOf(to), sharesTransferred, "balance to");
        }
    }

    function testTransferZeroAddress(uint256 shares) public {
        shares = bound(shares, 0, MAX_TEST_SHARES);
        vault.mint(shares, address(this));
        vm.expectRevert(ErrorsLib.ZeroAddress.selector);
        vault.transfer(address(0), shares);
    }

    function testTransferFrom(
        address from,
        address to,
        uint256 shares,
        uint256 sharesTransferred,
        uint256 sharesApproved
    ) public {
        vm.assume(shares <= MAX_TEST_SHARES);
        sharesApproved = bound(sharesApproved, 0, shares);
        sharesTransferred = bound(sharesTransferred, 0, sharesApproved);

        vm.assume(from != address(0));
        vm.assume(to != address(0));
        vault.mint(shares, from);

        vm.prank(from);
        vault.approve(address(this), sharesApproved);

        if (address(this) != from) {
            vm.expectEmit();
            emit EventsLib.AllowanceUpdatedByTransferFrom(from, address(this), sharesApproved - sharesTransferred);
        }

        vm.expectEmit();
        emit EventsLib.Transfer(from, to, sharesTransferred);

        vault.transferFrom(from, to, sharesTransferred);

        if (address(this) != from) {
            assertEq(vault.allowance(from, address(this)), sharesApproved - sharesTransferred, "approved-transferred");
        } else {
            assertEq(vault.allowance(from, address(this)), sharesApproved, "approved");
        }
        if (from == to) {
            assertEq(vault.balanceOf(from), shares, "balance");
        } else {
            assertEq(vault.balanceOf(from), shares - sharesTransferred, "balance from");
            assertEq(vault.balanceOf(to), sharesTransferred, "balance to");
        }
    }

    function testTransferFromSenderZeroAddress(address to) public {
        vm.assume(to != address(0));
        vm.expectRevert(ErrorsLib.ZeroAddress.selector);
        vault.transferFrom(address(0), to, 0);
        vm.stopPrank();
    }

    function testTransferFromReceiverZeroAddress(address from, uint256 shares) public {
        shares = bound(shares, 0, MAX_TEST_SHARES);
        vm.assume(from != address(0));
        vault.mint(shares, from);
        vm.prank(from);
        vault.approve(address(this), type(uint256).max);
        vm.expectRevert(ErrorsLib.ZeroAddress.selector);
        vault.transferFrom(from, address(0), shares);
    }

    function testInfiniteApproveTransferFrom(address from, address to, uint256 shares, uint256 sharesTransferred)
        public
    {
        shares = bound(shares, 0, MAX_TEST_SHARES);
        sharesTransferred = bound(sharesTransferred, 0, shares);

        vm.assume(from != address(0));
        vm.assume(to != address(0));
        vault.mint(shares, from);

        vm.prank(from);
        vault.approve(address(this), type(uint256).max);

        vm.expectEmit();
        emit EventsLib.Transfer(from, to, sharesTransferred);

        vault.transferFrom(from, to, sharesTransferred);
        assertEq(vault.allowance(from, address(this)), type(uint256).max, "allowance");
        if (from == to) {
            assertEq(vault.balanceOf(from), shares, "balance");
        } else {
            assertEq(vault.balanceOf(from), shares - sharesTransferred, "balance from");
            assertEq(vault.balanceOf(to), sharesTransferred, "balance to");
        }
    }

    function testCreateTooManyAssetsReverts() public {
        vault.deposit(type(uint128).max, address(this));
        vm.expectRevert(stdError.arithmeticError);
        vault.deposit(1, address(this));
    }

    function testCreateTooManySharesReverts() public {
        vm.assume(vault.virtualShares() < type(uint256).max / type(uint128).max);
        vault.mint(type(uint128).max * vault.virtualShares(), address(this));
        vm.expectRevert(stdError.arithmeticError);
        vault.mint(1, address(this));
    }

    function testTransferInsufficientBalanceReverts(address to, uint256 shares) public {
        shares = bound(shares, 0, MAX_TEST_SHARES);
        vm.assume(to != address(0));
        vault.mint(shares, address(this));
        vm.expectRevert(stdError.arithmeticError);
        vault.transfer(to, shares + 1);
    }

    function testTransferFromInsufficientAllowanceReverts(address from, address to, uint256 allowance) public {
        vm.assume(from != address(0));
        vm.assume(to != address(0));
        vm.assume(from != address(this));

        allowance = bound(allowance, 0, MAX_TEST_SHARES);
        vault.mint(allowance + 1, from);

        vm.prank(from);
        vault.approve(address(this), allowance);

        vm.expectRevert(stdError.arithmeticError);
        vault.transferFrom(from, to, allowance + 1);
    }

    function testTransferFromInsufficientBalanceReverts(address from, address to, uint256 allowance) public {
        vm.assume(from != address(0));
        vm.assume(to != address(0));
        allowance = bound(allowance, 1, MAX_TEST_SHARES);
        vault.mint(allowance - 1, from);

        vm.prank(from);
        vault.approve(address(this), allowance);

        vm.expectRevert(stdError.arithmeticError);
        vault.transferFrom(from, to, allowance);
    }

    function testDeleteSharesInsufficientBalanceReverts(address to, uint256 createShares, uint256 deletedShares)
        public
    {
        vm.assume(to != address(0));
        createShares = bound(createShares, 0, MAX_TEST_SHARES);
        deletedShares = _bound(deletedShares, createShares + 1, type(uint256).max);

        vault.mint(createShares, to);
        vm.expectRevert(stdError.arithmeticError);
        vault.redeem(deletedShares, to, to);
    }

    function testPermitOK(PermitInfo calldata p, address to, uint256 shares) public {
        (address owner, uint256 privateKey, uint256 nonce, uint256 deadline) = _setupPermit(p);
        _setCurrentNonce(owner, nonce);

        (uint8 v, bytes32 r, bytes32 s) = _signPermit(privateKey, owner, to, shares, nonce, deadline);

        vm.expectEmit();
        emit EventsLib.Approval(owner, to, shares);
        vm.expectEmit();
        emit EventsLib.Permit(owner, to, shares, nonce, deadline);

        vault.permit(owner, to, shares, deadline, v, r, s);
        assertEq(vault.allowance(owner, to), shares);
        assertEq(vault.nonces(owner), nonce + 1);
    }

    function testPermitBadOwnerReverts(PermitInfo calldata p, address to, uint256 shares, address badOwner) public {
        (address owner, uint256 privateKey, uint256 nonce, uint256 deadline) = _setupPermit(p);
        _setCurrentNonce(owner, nonce);

        vm.assume(owner != badOwner);

        (uint8 v, bytes32 r, bytes32 s) = _signPermit(privateKey, badOwner, to, shares, nonce, deadline);

        vm.expectRevert(ErrorsLib.InvalidSigner.selector);
        vault.permit(owner, to, shares, deadline, v, r, s);
    }

    function testPermitBadSpenderReverts(PermitInfo calldata p, address to, uint256 shares, address badSpender)
        public
    {
        (address owner, uint256 privateKey, uint256 nonce, uint256 deadline) = _setupPermit(p);
        _setCurrentNonce(owner, nonce);

        vm.assume(to != badSpender);

        (uint8 v, bytes32 r, bytes32 s) = _signPermit(privateKey, owner, badSpender, shares, nonce, deadline);

        vm.expectRevert(ErrorsLib.InvalidSigner.selector);
        vault.permit(owner, to, shares, deadline, v, r, s);
    }

    function testPermitBadNonceReverts(PermitInfo calldata p, address to, uint256 shares, uint256 badNonce) public {
        (address owner, uint256 privateKey, uint256 nonce, uint256 deadline) = _setupPermit(p);
        _setCurrentNonce(owner, nonce);

        vm.assume(nonce != badNonce);

        (uint8 v, bytes32 r, bytes32 s) = _signPermit(privateKey, owner, to, shares, badNonce, deadline);

        vm.expectRevert(ErrorsLib.InvalidSigner.selector);
        vault.permit(owner, to, shares, deadline, v, r, s);
    }

    function testPermitBadDeadlineReverts(PermitInfo calldata p, address to, uint256 shares, uint256 badDeadline)
        public
    {
        (address owner, uint256 privateKey, uint256 nonce, uint256 deadline) = _setupPermit(p);
        _setCurrentNonce(owner, nonce);

        badDeadline = bound(badDeadline, block.timestamp, type(uint256).max - 1);
        vm.assume(badDeadline != deadline);

        (uint8 v, bytes32 r, bytes32 s) = _signPermit(privateKey, owner, to, shares, nonce, badDeadline);

        vm.expectRevert(ErrorsLib.InvalidSigner.selector);
        vault.permit(owner, to, shares, deadline, v, r, s);
    }

    function testPermitPastDeadlineReverts(PermitInfo calldata p, address to, uint256 shares) public {
        (address owner, uint256 privateKey, uint256 nonce, uint256 deadline) = _setupPermit(p);
        _setCurrentNonce(owner, nonce);

        deadline = bound(deadline, 0, block.timestamp - 1);

        (uint8 v, bytes32 r, bytes32 s) = _signPermit(privateKey, owner, to, shares, nonce, deadline);

        vm.expectRevert(ErrorsLib.PermitDeadlineExpired.selector);
        vault.permit(owner, to, shares, deadline, v, r, s);
    }

    function testPermitReplayReverts(PermitInfo calldata p, address to, uint256 shares) public {
        (address owner, uint256 privateKey, uint256 nonce, uint256 deadline) = _setupPermit(p);
        nonce = bound(nonce, 0, type(uint256).max - 2);
        _setCurrentNonce(owner, nonce);

        (uint8 v, bytes32 r, bytes32 s) = _signPermit(privateKey, owner, to, shares, nonce, deadline);

        vault.permit(owner, to, shares, deadline, v, r, s);
        vm.expectRevert(ErrorsLib.InvalidSigner.selector);
        vault.permit(owner, to, shares, deadline, v, r, s);
    }
}
