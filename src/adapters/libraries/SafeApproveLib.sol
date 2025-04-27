// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.28;

import {IERC20} from "../../interfaces/IERC20.sol";
import {ErrorsLib} from "../../libraries/ErrorsLib.sol";

library SafeApproveLib {
    error ApproveReverted();
    error ApproveReturnedFalse();

    function safeApprove(address token, address spender, uint256 value) internal {
        require(token.code.length > 0, ErrorsLib.NoCode());

        (bool success, bytes memory returndata) = token.call(abi.encodeCall(IERC20.approve, (spender, value)));
        require(success, ApproveReverted());
        require(returndata.length == 0 || abi.decode(returndata, (bool)), ApproveReturnedFalse());
    }
}
