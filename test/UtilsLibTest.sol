// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.28;

import "./BaseTest.sol";
import {stdError} from "../lib/forge-std/src/StdError.sol";
import {UtilsLib} from "../src/libraries/UtilsLib.sol";
import {VaultV2} from "../src/VaultV2.sol";
import {min} from "./BaseTest.sol";

contract ReturnsInput {
    fallback() external {
        bytes memory data = msg.data;
        assembly {
            return(add(data, 32), mload(data))
        }
    }
}

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

contract ControlledStaticCallTest is BaseTest {
    function testDataWrongSize(bytes calldata data) public {
        vm.assume(data.length != 32);
        address account = address(new ReturnsInput());
        uint256 output = UtilsLib.controlledStaticCall(account, data);
        assertEq(output, 0);
    }

    function testSuccess(bytes32 dataBytes32) public {
        bytes memory data = bytes.concat(dataBytes32);
        address account = address(new ReturnsInput());
        uint256 output = UtilsLib.controlledStaticCall(account, data);
        assertEq(output, uint256(bytes32(data)));
    }

    function testNoCode(bytes calldata data) public {
        address account = makeAddr("no code");

        uint256 output = UtilsLib.controlledStaticCall(account, data);
        assertEq(output, 0);
    }

    function testRevert(bytes calldata data) public {
        address account = address(new Reverts());
        (bool success, bytes memory returnData) = account.staticcall(data);
        assertFalse(success);
        assertEq(returnData.length, data.length);

        uint256 output = UtilsLib.controlledStaticCall(account, data);
        assertEq(output, 0);
    }

    function testReturnsNoData(bytes calldata data) public {
        address account = address(new ReturnsNothing());
        (bool success, bytes memory returnData) = account.staticcall(data);
        assertTrue(success);
        assertEq(returnData.length, 0);

        uint256 output = UtilsLib.controlledStaticCall(account, data);
        assertEq(output, 0);
    }

    function testReturnsBomb(bytes calldata) public {
        address account = address(new ReturnsBomb());

        // Would revert if returned data was entirely copied to memory.
        uint256 gas = 4953 * 2;
        this._testReturnsBomb{gas: gas}(account);
    }

    function testReturnBombLowLevelStaticCall(bytes calldata) public {
        address account = address(new ReturnsBomb());

        uint256 gas = 4953 * 2;
        vm.expectRevert();
        this._testReturnsBombLowLevelStaticCall{gas: gas}(account);
    }

    /* INTERNAL */

    function _testReturnsBomb(address account) external view {
        UtilsLib.controlledStaticCall(account, hex"");
    }

    function _testReturnsBombLowLevelStaticCall(address account) external view {
        (bool success,) = account.staticcall(hex"");
        success; // No-op to silence warning.
    }
}
