// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.28;

import "./BaseTest.sol";
import {stdError} from "forge-std/StdError.sol";
import {ErrorsLib} from "../src/libraries/ErrorsLib.sol";
import {DOMAIN_TYPEHASH, PERMIT_TYPEHASH} from "../src/libraries/ConstantsLib.sol";
import {stdStorage, StdStorage} from "forge-std/Test.sol";

contract ERC20Test is BaseTest {
    using stdStorage for StdStorage;

    uint256 constant MAX_DEPOSIT = 1e18 ether;

    struct PermitInfo {
        uint256 privateKey;
        uint256 nonce;
        uint256 deadline;
    }

    function _signPermit(uint256 privateKey, address owner, address to, uint256 amount, uint256 nonce, uint256 deadline)
        internal
        view
        returns (uint8, bytes32, bytes32)
    {
        bytes32 hashStruct = keccak256(abi.encode(PERMIT_TYPEHASH, owner, to, amount, nonce, deadline));
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", vault.DOMAIN_SEPARATOR(), hashStruct));
        return vm.sign(privateKey, digest);
    }

    function _setupPermit(PermitInfo calldata p)
        internal
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

    function testMint(uint256 amount) public {
        vm.assume(amount <= MAX_DEPOSIT);

        vm.expectEmit();
        emit IVaultV2.Transfer(address(0), address(this), amount);

        vault.mint(amount, address(this));
        assertEq(vault.totalSupply(), amount, "total supply");
        assertEq(vault.balanceOf(address(this)), amount, "balance");
    }

    function testMintZeroAddress(uint256 amount) public {
        vm.expectRevert(ErrorsLib.ZeroAddress.selector);
        vault.mint(amount, address(0));
    }

    function testBurn(uint256 amount, uint256 amountRedeemed) public {
        vm.assume(amount <= MAX_DEPOSIT);
        amountRedeemed = bound(amountRedeemed, 0, amount);

        vault.mint(amount, address(this));
        vm.expectEmit();
        emit IVaultV2.Transfer(address(this), address(0), amountRedeemed);

        vault.redeem(amountRedeemed, address(this), address(this));

        assertEq(vault.totalSupply(), amount - amountRedeemed, "total supply");
        assertEq(vault.balanceOf(address(this)), amount - amountRedeemed, "balance");
    }

    function testBurnZeroAddress() public {
        vm.expectRevert(ErrorsLib.ZeroAddress.selector);
        vault.redeem(0, address(this), address(0));
    }

    function testApprove(address spender, uint256 amount) public {
        vm.assume(amount <= MAX_DEPOSIT);
        vm.expectEmit();
        emit IVaultV2.Approval(address(this), address(spender), amount);

        assertTrue(vault.approve(spender, amount));
        assertEq(vault.allowance(address(this), spender), amount);
    }

    function testTransfer(address to, uint256 amount, uint256 amountTransferred) public {
        vm.assume(amount <= MAX_DEPOSIT);
        vm.assume(to != address(0));
        amountTransferred = bound(amountTransferred, 0, amount);

        vault.mint(amount, address(this));

        vm.expectEmit();
        emit IVaultV2.Transfer(address(this), address(to), amountTransferred);

        assertTrue(vault.transfer(to, amountTransferred));

        assertEq(vault.totalSupply(), amount, "total supply");
        if (address(this) == to) {
            assertEq(vault.balanceOf(address(this)), amount, "balance");
        } else {
            assertEq(vault.balanceOf(address(this)), amount - amountTransferred, "balance from");
            assertEq(vault.balanceOf(to), amountTransferred, "balance to");
        }
    }

    function testTransferZeroAddress(uint256 amount) public {
        vault.mint(amount, address(this));
        vm.expectRevert(ErrorsLib.ZeroAddress.selector);
        vault.transfer(address(0), amount);
    }

    function testTransferFrom(
        address from,
        address to,
        uint256 amount,
        uint256 amountTransferred,
        uint256 amountApproved
    ) public {
        vm.assume(amount <= MAX_DEPOSIT);
        amountApproved = bound(amountApproved, 0, amount);
        amountTransferred = bound(amountTransferred, 0, amountApproved);

        vm.assume(from != address(0));
        vm.assume(to != address(0));
        vault.mint(amount, from);

        vm.prank(from);
        vault.approve(address(this), amountApproved);

        vm.expectEmit();
        emit IVaultV2.Transfer(from, to, amountTransferred);
        vault.transferFrom(from, to, amountTransferred);

        assertEq(vault.allowance(from, address(this)), amountApproved - amountTransferred, "allowance");
        if (from == to) {
            assertEq(vault.balanceOf(from), amount, "balance");
        } else {
            assertEq(vault.balanceOf(from), amount - amountTransferred, "balance from");
            assertEq(vault.balanceOf(to), amountTransferred, "balance to");
        }
    }

    function testTransferFromSenderZeroAddress(address to) public {
        vm.assume(to != address(0));
        vm.expectRevert(ErrorsLib.ZeroAddress.selector);
        vault.transferFrom(address(0), to, 0);
        vm.stopPrank();
    }

    function testTransferFromReceiverZeroAddress(address from, uint256 amount) public {
        vm.assume(from != address(0));
        vault.mint(amount, from);
        vm.prank(from);
        vault.approve(address(this), type(uint256).max);
        vm.expectRevert(ErrorsLib.ZeroAddress.selector);
        vault.transferFrom(from, address(0), amount);
    }

    function testInfiniteApproveTransferFrom(address from, address to, uint256 amount, uint256 amountTransferred)
        public
    {
        vm.assume(amount <= MAX_DEPOSIT);
        amountTransferred = bound(amountTransferred, 0, amount);

        vm.assume(from != address(0));
        vm.assume(to != address(0));
        vault.mint(amount, from);

        vm.prank(from);
        vault.approve(address(this), type(uint256).max);

        vm.expectEmit();
        emit IVaultV2.Transfer(from, to, amountTransferred);

        vault.transferFrom(from, to, amountTransferred);
        assertEq(vault.allowance(from, address(this)), type(uint256).max, "allowance");
        if (from == to) {
            assertEq(vault.balanceOf(from), amount, "balance");
        } else {
            assertEq(vault.balanceOf(from), amount - amountTransferred, "balance from");
            assertEq(vault.balanceOf(to), amountTransferred, "balance to");
        }
    }

    function testMintOverMaxUintReverts() public {
        vault.mint(type(uint256).max, address(this));
        vm.expectRevert(stdError.arithmeticError);
        vault.mint(1, address(this));
    }

    function testTransferInsufficientBalanceReverts(address to, uint256 amount) public {
        amount = bound(amount, 0, type(uint256).max - 1);
        vm.assume(to != address(0));
        vault.mint(amount, address(this));
        vm.expectRevert(stdError.arithmeticError);
        vault.transfer(to, amount + 1);
    }

    function testTransferFromInsufficientAllowanceReverts(address from, address to, uint256 allowance) public {
        vm.assume(from != address(0));
        vm.assume(to != address(0));

        allowance = bound(allowance, 0, type(uint256).max - 1);
        vault.mint(allowance + 1, from);

        vm.prank(from);
        vault.approve(address(this), allowance);

        vm.expectRevert(stdError.arithmeticError);
        vault.transferFrom(from, to, allowance + 1);
    }

    function testTransferFromInsufficientBalanceReverts(address from, address to, uint256 allowance) public {
        vm.assume(from != address(0));
        vm.assume(to != address(0));
        allowance = bound(allowance, 1, type(uint256).max);
        vault.mint(allowance - 1, from);

        vm.prank(from);
        vault.approve(address(this), allowance);

        vm.expectRevert(stdError.arithmeticError);
        vault.transferFrom(from, to, allowance);
    }

    function testBurnInsufficientBalanceReverts(address to, uint256 mintAmount, uint256 burnAmount) public {
        vm.assume(to != address(0));
        mintAmount = bound(mintAmount, 0, type(uint256).max - 1);
        burnAmount = _bound(burnAmount, mintAmount + 1, type(uint256).max);

        vault.mint(mintAmount, to);
        vm.expectRevert(stdError.arithmeticError);
        vault.redeem(burnAmount, to, to);
    }

    function testPermitOK(PermitInfo calldata p, address to, uint256 amount) public {
        (address owner, uint256 privateKey, uint256 nonce, uint256 deadline) = _setupPermit(p);
        _setCurrentNonce(owner, nonce);

        (uint8 v, bytes32 r, bytes32 s) = _signPermit(privateKey, owner, to, amount, nonce, deadline);

        vm.expectEmit();
        emit EventsLib.Approval(owner, to, amount);

        vault.permit(owner, to, amount, deadline, v, r, s);
        assertEq(vault.allowance(owner, to), amount);
        assertEq(vault.nonces(owner), nonce + 1);
    }

    function testPermitBadOwnerReverts(PermitInfo calldata p, address to, uint256 amount, address badOwner) public {
        (address owner, uint256 privateKey, uint256 nonce, uint256 deadline) = _setupPermit(p);
        _setCurrentNonce(owner, nonce);

        vm.assume(owner != badOwner);

        (uint8 v, bytes32 r, bytes32 s) = _signPermit(privateKey, badOwner, to, amount, nonce, deadline);

        vm.expectRevert(ErrorsLib.InvalidSigner.selector);
        vault.permit(owner, to, amount, deadline, v, r, s);
    }

    function testPermitBadSpenderReverts(PermitInfo calldata p, address to, uint256 amount, address badSpender)
        public
    {
        (address owner, uint256 privateKey, uint256 nonce, uint256 deadline) = _setupPermit(p);
        _setCurrentNonce(owner, nonce);

        vm.assume(to != badSpender);

        (uint8 v, bytes32 r, bytes32 s) = _signPermit(privateKey, owner, badSpender, amount, nonce, deadline);

        vm.expectRevert(ErrorsLib.InvalidSigner.selector);
        vault.permit(owner, to, amount, deadline, v, r, s);
    }

    function testPermitBadNonceReverts(PermitInfo calldata p, address to, uint256 amount, uint256 badNonce) public {
        (address owner, uint256 privateKey, uint256 nonce, uint256 deadline) = _setupPermit(p);
        _setCurrentNonce(owner, nonce);

        vm.assume(nonce != badNonce);

        (uint8 v, bytes32 r, bytes32 s) = _signPermit(privateKey, owner, to, amount, badNonce, deadline);

        vm.expectRevert(ErrorsLib.InvalidSigner.selector);
        vault.permit(owner, to, amount, deadline, v, r, s);
    }

    function testPermitBadDeadlineReverts(PermitInfo calldata p, address to, uint256 amount, uint256 badDeadline)
        public
    {
        (address owner, uint256 privateKey, uint256 nonce, uint256 deadline) = _setupPermit(p);
        _setCurrentNonce(owner, nonce);

        badDeadline = bound(badDeadline, block.timestamp, type(uint256).max - 1);
        vm.assume(badDeadline != deadline);

        (uint8 v, bytes32 r, bytes32 s) = _signPermit(privateKey, owner, to, amount, nonce, badDeadline);

        vm.expectRevert(ErrorsLib.InvalidSigner.selector);
        vault.permit(owner, to, amount, deadline, v, r, s);
    }

    function testPermitPastDeadlineReverts(PermitInfo calldata p, address to, uint256 amount) public {
        (address owner, uint256 privateKey, uint256 nonce, uint256 deadline) = _setupPermit(p);
        _setCurrentNonce(owner, nonce);

        deadline = bound(deadline, 0, block.timestamp - 1);

        (uint8 v, bytes32 r, bytes32 s) = _signPermit(privateKey, owner, to, amount, nonce, deadline);

        vm.expectRevert(ErrorsLib.PermitDeadlineExpired.selector);
        vault.permit(owner, to, amount, deadline, v, r, s);
    }

    function testPermitReplayReverts(PermitInfo calldata p, address to, uint256 amount) public {
        (address owner, uint256 privateKey, uint256 nonce, uint256 deadline) = _setupPermit(p);
        nonce = bound(nonce, 0, type(uint256).max - 2);
        _setCurrentNonce(owner, nonce);

        (uint8 v, bytes32 r, bytes32 s) = _signPermit(privateKey, owner, to, amount, nonce, deadline);

        vault.permit(owner, to, amount, deadline, v, r, s);
        vm.expectRevert(ErrorsLib.InvalidSigner.selector);
        vault.permit(owner, to, amount, deadline, v, r, s);
    }
}
