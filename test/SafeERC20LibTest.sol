// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import "./BaseTest.sol";
import "../src/libraries/SafeERC20Lib.sol";

/// @dev Token not returning any boolean.
contract ERC20WithoutBoolean {
    function transfer(address to, uint256 amount) public {}
    function transferFrom(address from, address to, uint256 amount) public {}
    function approve(address spender, uint256 amount) public {}
}

/// @dev Token returning false.
contract ERC20WithBooleanAlwaysFalse {
    function transfer(address to, uint256 amount) public returns (bool res) {}
    function transferFrom(address from, address to, uint256 amount) public returns (bool res) {}
    function approve(address, uint256) public pure returns (bool res) {}
}

/// @dev Normal token.
contract ERC20Normal {
    address public recordedFrom;
    address public recordedTo;
    uint256 public recordedAmount;
    uint256 public recordedAllowance;
    address public recordedSpender;

    function transfer(address to, uint256 amount) public returns (bool) {
        recordedTo = to;
        recordedAmount = amount;
        return true;
    }

    function transferFrom(address from, address to, uint256 amount) public returns (bool) {
        recordedFrom = from;
        recordedTo = to;
        recordedAmount = amount;
        return true;
    }

    function approve(address spender, uint256 amount) public returns (bool) {
        recordedSpender = spender;
        recordedAmount = amount;
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

    function testSafeTransfer(address to, uint256 amount) public {
        // No code.
        vm.expectRevert(ErrorsLib.NoCode.selector);
        this.safeTransfer(address(1), to, amount);

        // Call unsuccessfull.
        vm.expectRevert(ErrorsLib.TransferReverted.selector);
        this.safeTransfer(address(this), to, amount);

        // Return false.
        vm.expectRevert(ErrorsLib.TransferReturnedFalse.selector);
        this.safeTransfer(address(tokenWithBooleanAlwaysFalse), to, amount);

        // Normal path.
        this.safeTransfer(address(tokenNormal), to, amount);
        this.safeTransfer(address(tokenWithoutBoolean), to, amount);
        assertEq(tokenNormal.recordedTo(), to);
        assertEq(tokenNormal.recordedAmount(), amount);
    }

    function testSafeTransferFrom(address from, address to, uint256 amount) public {
        // No code.
        vm.expectRevert(ErrorsLib.NoCode.selector);
        this.safeTransferFrom(address(1), from, to, amount);

        // Call unsuccessfull.
        vm.expectRevert(ErrorsLib.TransferFromReverted.selector);
        this.safeTransferFrom(address(this), from, to, amount);

        // Return false.
        vm.expectRevert(ErrorsLib.TransferFromReturnedFalse.selector);
        this.safeTransferFrom(address(tokenWithBooleanAlwaysFalse), from, to, amount);

        // Normal path.
        this.safeTransferFrom(address(tokenNormal), from, to, amount);
        this.safeTransferFrom(address(tokenWithoutBoolean), from, to, amount);
        assertEq(tokenNormal.recordedFrom(), from);
        assertEq(tokenNormal.recordedTo(), to);
        assertEq(tokenNormal.recordedAmount(), amount);
    }

    function testSafeApprove(address spender, uint256 amount) public {
        // No code.
        vm.expectRevert(ErrorsLib.NoCode.selector);
        this.safeApprove(address(1), spender, amount);

        // Call unsuccessfull.
        vm.expectRevert(ErrorsLib.ApproveReverted.selector);
        this.safeApprove(address(this), spender, amount);

        // Return false.
        vm.expectRevert(ErrorsLib.ApproveReturnedFalse.selector);
        this.safeApprove(address(tokenWithBooleanAlwaysFalse), spender, amount);

        // Normal path.
        this.safeApprove(address(tokenNormal), spender, amount);
        this.safeApprove(address(tokenWithoutBoolean), spender, amount);
        assertEq(tokenNormal.recordedSpender(), spender);
        assertEq(tokenNormal.recordedAmount(), amount);
    }

    // helpers (needed for expect revert)
    function safeTransfer(address token, address to, uint256 amount) external {
        SafeERC20Lib.safeTransfer(token, to, amount);
    }

    function safeTransferFrom(address token, address from, address to, uint256 amount) external {
        SafeERC20Lib.safeTransferFrom(token, from, to, amount);
    }

    function safeApprove(address token, address spender, uint256 amount) external {
        SafeERC20Lib.safeApprove(token, spender, amount);
    }
}
