// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.28;

import {Test, console} from "../lib/forge-std/src/Test.sol";
import {stdError} from "../lib/forge-std/src/StdError.sol";
import {UtilsLib} from "../src/libraries/UtilsLib.sol";
import {VaultV2} from "../src/VaultV2.sol";

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

contract BurnsAllGas {
    fallback() external {
        assembly {
            invalid()
        }
    }
}

contract ControlledStaticCallTest is Test {
    function testSuccess(bytes calldata data) public {
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
        uint256 output = UtilsLib.controlledStaticCall(account, data);
        assertEq(output, 0);
    }

    function testReturnsNoData(bytes calldata data) public {
        address account = address(new ReturnsNothing());
        uint256 output = UtilsLib.controlledStaticCall(account, data);
        assertEq(output, 0);
    }

    function testReturnsBomb(bytes calldata) public {
        address account = address(new ReturnsBomb());
        // Would revert if returned data was entirely copied to memory.
        uint256 gas = 4953 * 2;
        this._testReturnsBomb{gas: gas}(account);
    }

    uint256 constant SAFE_GAS_AMOUNT = 500_000;

    function testCanUpdateVicIfVicBurnsAllGas() public {
        BurnsAllGas burnsAllGas = new BurnsAllGas();
        VaultV2 vault = new VaultV2(address(this), address(0));
        vault.setCurator(address(this));

        vault.submit(abi.encodeCall(vault.setVic, (address(burnsAllGas))));
        vault.setVic(address(burnsAllGas));

        skip(1);
        // check that vic can still be changed
        vault.submit(abi.encodeCall(vault.setVic, (address(0))));
        vault.setVic{gas: SAFE_GAS_AMOUNT}(address(0));

        // check that gas was almost entirely burned
        assertGt(vm.lastCallGas().gasTotalUsed, 0.9e18 * SAFE_GAS_AMOUNT / 1e18);
    }

    /* INTERNAL */

    function _testReturnsBomb(address account) external view {
        UtilsLib.controlledStaticCall(account, hex"");
    }
}
