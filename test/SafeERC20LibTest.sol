// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Morpho Association
pragma solidity ^0.8.0;

import "./BaseTest.sol";
import "../src/libraries/SafeERC20Lib.sol";

/// @dev Token not returning any boolean.
contract ERC20WithoutBoolean {
    function transfer(address to, uint256 value) public {}
    function transferFrom(address from, address to, uint256 value) public {}
    function approve(address spender, uint256 value) public {}
}

/// @dev Token returning false.
contract ERC20WithBooleanAlwaysFalse {
    function transfer(address to, uint256 value) public returns (bool res) {}
    function transferFrom(address from, address to, uint256 value) public returns (bool res) {}
    function approve(address, uint256) public pure returns (bool res) {}
}

/// @dev Normal token.
contract ERC20Normal {
    address public recordedFrom;
    address public recordedTo;
    uint256 public recordedValue;
    uint256 public recordedAllowance;
    address public recordedSpender;

    function transfer(address to, uint256 value) public returns (bool) {
        recordedTo = to;
        recordedValue = value;
        return true;
    }

    function transferFrom(address from, address to, uint256 value) public returns (bool) {
        recordedFrom = from;
        recordedTo = to;
        recordedValue = value;
        return true;
    }

    function approve(address spender, uint256 value) public returns (bool) {
        recordedSpender = spender;
        recordedValue = value;
        return true;
    }
}

contract SafeERC20LibTest is Test {
    ERC20Normal public tokenNormal;
    ERC20WithoutBoolean public tokenWithoutBoolean;
    ERC20WithBooleanAlwaysFalse public tokenWithBooleanAlwaysFalse;

    function setUp() public {
        tokenNormal = new ERC20Normal();
        tokenWithoutBoolean = new ERC20WithoutBoolean();
        tokenWithBooleanAlwaysFalse = new ERC20WithBooleanAlwaysFalse();
    }

    function testSafeTransfer(address to, uint256 value) public {
        // No code.
        vm.expectRevert(ErrorsLib.NoCode.selector);
        this.safeTransfer(address(1), to, value);

        // Call unsuccessful.
        vm.expectRevert(ErrorsLib.TransferReverted.selector);
        this.safeTransfer(address(this), to, value);

        // Return false.
        vm.expectRevert(ErrorsLib.TransferReturnedFalse.selector);
        this.safeTransfer(address(tokenWithBooleanAlwaysFalse), to, value);

        // Normal path.
        this.safeTransfer(address(tokenNormal), to, value);
        this.safeTransfer(address(tokenWithoutBoolean), to, value);
        assertEq(tokenNormal.recordedTo(), to);
        assertEq(tokenNormal.recordedValue(), value);
    }

    function testSafeTransferFrom(address from, address to, uint256 value) public {
        // No code.
        vm.expectRevert(ErrorsLib.NoCode.selector);
        this.safeTransferFrom(address(1), from, to, value);

        // Call unsuccessful.
        vm.expectRevert(ErrorsLib.TransferFromReverted.selector);
        this.safeTransferFrom(address(this), from, to, value);

        // Return false.
        vm.expectRevert(ErrorsLib.TransferFromReturnedFalse.selector);
        this.safeTransferFrom(address(tokenWithBooleanAlwaysFalse), from, to, value);

        // Normal path.
        this.safeTransferFrom(address(tokenNormal), from, to, value);
        this.safeTransferFrom(address(tokenWithoutBoolean), from, to, value);
        assertEq(tokenNormal.recordedFrom(), from);
        assertEq(tokenNormal.recordedTo(), to);
        assertEq(tokenNormal.recordedValue(), value);
    }

    function testSafeApprove(address spender, uint256 value) public {
        // No code.
        vm.expectRevert(ErrorsLib.NoCode.selector);
        this.safeApprove(address(1), spender, value);

        // Call unsuccessful.
        vm.expectRevert(ErrorsLib.ApproveReverted.selector);
        this.safeApprove(address(this), spender, value);

        // Return false.
        vm.expectRevert(ErrorsLib.ApproveReturnedFalse.selector);
        this.safeApprove(address(tokenWithBooleanAlwaysFalse), spender, value);

        // Normal path.
        this.safeApprove(address(tokenNormal), spender, value);
        this.safeApprove(address(tokenWithoutBoolean), spender, value);
        assertEq(tokenNormal.recordedSpender(), spender);
        assertEq(tokenNormal.recordedValue(), value);
    }

    /* HELPERS */

    function safeTransfer(address token, address to, uint256 value) external {
        SafeERC20Lib.safeTransfer(token, to, value);
    }

    function safeTransferFrom(address token, address from, address to, uint256 value) external {
        SafeERC20Lib.safeTransferFrom(token, from, to, value);
    }

    function safeApprove(address token, address spender, uint256 value) external {
        SafeERC20Lib.safeApprove(token, spender, value);
    }
}
