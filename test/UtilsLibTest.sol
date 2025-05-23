// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.28;

import {Test, console} from "../lib/forge-std/src/Test.sol";
import {stdError} from "../lib/forge-std/src/StdError.sol";
import {UtilsLib} from "../src/libraries/UtilsLib.sol";

contract Reverts {
    fallback() external {
        bytes memory data = msg.data;
        assembly {
            revert(add(data, 32), mload(data))
        }
    }
}

contract ReturnsNothing {
    fallback() external {
        assembly {
            return(0, 0)
        }
    }
}

contract ReturnsBomb {
    fallback() external {
        // expansion cost: 3 * words + floor(words**2/512) = 4953
        uint256 words = 1e3;
        assembly {
            mstore(mul(sub(words, 1), 32), 1)
            return(0, mul(words, 32))
        }
    }
}

contract UtilsLibTest is Test {
    function testStaticCallNoCode(bytes calldata data) public {
        address account = makeAddr("no code");
        uint256 output = UtilsLib.controlledStaticCall(account, data);
        assertEq(output, 0);
    }

    function testStaticCallRevert(bytes calldata data) public {
        address account = address(new Reverts());
        uint256 output = UtilsLib.controlledStaticCall(account, data);
        assertEq(output, 0);
    }

    function testStaticCallReturnsNoData(bytes calldata data) public {
        address account = address(new ReturnsNothing());
        uint256 output = UtilsLib.controlledStaticCall(account, data);
        assertEq(output, 0);
    }

    function testStaticCallReturnsBomb(bytes calldata) public {
        address account = address(new ReturnsBomb());
        // Will revert if returned data is entirely copied to memory
        uint256 gas = 4953 * 2;
        this._testReturnsBomb{gas: gas}(account);
    }

    function testCallNoCode(bytes calldata data) public {
        address account = makeAddr("no code");
        uint256 output = UtilsLib.controlledCall(account, data);
        assertEq(output, 0);
    }

    function testCallRevert(bytes calldata data) public {
        address account = address(new Reverts());
        uint256 output = UtilsLib.controlledCall(account, data);
        assertEq(output, 0);
    }

    function testCallReturnsNoData(bytes calldata data) public {
        address account = address(new ReturnsNothing());
        uint256 output = UtilsLib.controlledCall(account, data);
        assertEq(output, 0);
    }

    function testCallReturnsBomb(bytes calldata) public {
        address account = address(new ReturnsBomb());
        // Will revert if returned data is entirely copied to memory
        uint256 gas = 4953 * 2;
        this._testReturnsBomb{gas: gas}(account);
    }

    /* INTERNAL */

    function _testReturnsBomb(address account) external view {
        UtilsLib.controlledStaticCall(account, hex"");
    }
}
