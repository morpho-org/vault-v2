// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.28;

import {IERC20} from "../interfaces/IERC20.sol";
import {ErrorsLib} from "./ErrorsLib.sol";

library SafeTransferLib {
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
}
