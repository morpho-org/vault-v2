// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Morpho Association
pragma solidity ^0.8.0;

import {IERC20} from "../interfaces/IERC20.sol";
import {ErrorsLib} from "./ErrorsLib.sol";

library SafeERC20Lib {
    function safeTransfer(address token, address to, uint256 value) internal {
        require(token.code.length > 0, ErrorsLib.NoCode());

        (bool success, bytes memory returndata) = token.call(abi.encodeCall(IERC20.transfer, (to, value)));
        require(success, ErrorsLib.TransferReverted());
        require(returndata.length == 0 || abi.decode(returndata, (bool)), ErrorsLib.TransferReturnedFalse());
    }

    function safeTransferFrom(address token, address from, address to, uint256 value) internal {
        require(token.code.length > 0, ErrorsLib.NoCode());

        (bool success, bytes memory returndata) = token.call(abi.encodeCall(IERC20.transferFrom, (from, to, value)));
        require(success, ErrorsLib.TransferFromReverted());
        require(returndata.length == 0 || abi.decode(returndata, (bool)), ErrorsLib.TransferFromReturnedFalse());
    }

    function safeApprove(address token, address spender, uint256 value) internal {
        require(token.code.length > 0, ErrorsLib.NoCode());

        (bool success, bytes memory returndata) = token.call(abi.encodeCall(IERC20.approve, (spender, value)));
        require(success, ErrorsLib.ApproveReverted());
        require(returndata.length == 0 || abi.decode(returndata, (bool)), ErrorsLib.ApproveReturnedFalse());
    }

    /// @dev Skips the approval when the current allowance is already at least 2^95 - 1 (some tokens like COMP and UNI have a max allowance of type(uint96).max).
    /// @dev Resets to 0 before re-approving to support USDT-like tokens.
    function forceApproveMax(address token, address spender) internal {
        if (IERC20(token).allowance(address(this), spender) >= type(uint96).max / 2) return;
        safeApprove(token, spender, 0);
        safeApprove(token, spender, type(uint256).max);
    }
}
