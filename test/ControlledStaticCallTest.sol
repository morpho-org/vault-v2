// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.28;

import {Test, console} from "../lib/forge-std/src/Test.sol";
import {stdError} from "../lib/forge-std/src/StdError.sol";
import {ERC20Mock} from "./mocks/ERC20Mock.sol";
import {UtilsLib} from "../src/libraries/UtilsLib.sol";
import {VaultV2} from "../src/VaultV2.sol";
import "../src/libraries/ConstantsLib.sol";

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

// Burn almost all gas and return toReturn.
contract BurnsAllGas {
    uint256 immutable returnValue;

    constructor(uint256 _returnValue) {
        returnValue = _returnValue;
    }

    fallback() external {
        // gasToMemoryExpansion uses 1021 gas. Update if needed.
        // Reserving 50 gas for the return subtraction and the return.
        uint256 burnAmount = gasleft() - 1021 - 50;
        uint256 words = gasToMemoryExpansion(burnAmount);
        uint256 _returnValue = returnValue;

        assembly ("memory-safe") {
            mstore(mul(sub(words, 1), 32), 1)
            mstore(0, _returnValue)
            return(0, 32)
        }
    }
}

// Burn an approximate amount of gas and return 1.
contract BurnsGas {
    uint256 immutable burnAmount;
    BurnsAllGas immutable burner;

    constructor(uint256 _burnAmount) {
        burnAmount = _burnAmount;
        burner = new BurnsAllGas(0);
    }

    fallback() external {
        (bool s, bytes memory r) = address(burner).call{gas: 64 * burnAmount / 63}("");
        // No-op to silence warning.
        s;
        r;
        // return 1
        assembly ("memory-safe") {
            mstore(0, 1)
            return(0, 32)
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

    uint256 constant GAS_BURNED_BY_GATE = 30_000;
    uint256 constant SAFE_GAS_AMOUNT = 8_000_000;

    function testCanUpdateVicIfVicBurnsAllGas() public {
        // Vault setup
        ERC20Mock asset = new ERC20Mock();
        VaultV2 vault = new VaultV2(address(this), address(asset));
        deal(address(asset), address(this), 1e18);
        asset.approve(address(vault), type(uint256).max);

        vault.setCurator(address(this));

        uint256 amount = 1e18;
        uint256 interestPerSecond = amount * MAX_RATE_PER_SECOND / WAD;

        // make accrueInterest as costly as possible
        // but keep gates cost reasonable since the gate can be changed without accruing interest
        // rationale is that it is OK for a shares gate to lock users anyway
        address gate = address(new BurnsGas(GAS_BURNED_BY_GATE));
        vault.submit(abi.encodeCall(vault.setSharesGate, (gate)));
        vault.setSharesGate(gate);

        address performanceFeeRecipient = makeAddr("performance fee recipient");
        vault.submit(abi.encodeCall(vault.setPerformanceFeeRecipient, (performanceFeeRecipient)));
        vault.setPerformanceFeeRecipient(performanceFeeRecipient);

        address managementFeeRecipient = makeAddr("management fee recipient");
        vault.submit(abi.encodeCall(vault.setManagementFeeRecipient, (managementFeeRecipient)));
        vault.setManagementFeeRecipient(managementFeeRecipient);

        vault.submit(abi.encodeCall(vault.setPerformanceFee, (MAX_PERFORMANCE_FEE)));
        vault.setPerformanceFee(MAX_PERFORMANCE_FEE);

        vault.submit(abi.encodeCall(vault.setManagementFee, (MAX_MANAGEMENT_FEE)));
        vault.setManagementFee(MAX_MANAGEMENT_FEE);

        vault.deposit(amount, address(this));

        BurnsAllGas burnsAllGas = new BurnsAllGas(interestPerSecond);
        vault.submit(abi.encodeCall(vault.setVic, (address(burnsAllGas))));
        vault.setVic(address(burnsAllGas));

        skip(2 weeks);
        // check that vic can still be changed
        vault.submit(abi.encodeCall(vault.setVic, (address(0))));
        vault.setVic{gas: SAFE_GAS_AMOUNT}(address(0));

        // check that gas was almost entirely burned
        assertGt(vm.lastCallGas().gasTotalUsed, SAFE_GAS_AMOUNT * 63 / 64);
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

/* FREE UTILITY FUNCTIONS */

// approximate the inverse of the memory expansion cost function
// cost function is g(w) = 3w + ⌊w²/512⌋.
// approximated to w(g) = [ sqrt(1536² + 4 * 512 * g) - 1536 ] / 2.
function gasToMemoryExpansion(uint256 gas) pure returns (uint256) {
    return (sqrt(1536 * 1536 + 4 * 512 * gas) - 1536) / 2;
}

// From
// https://github.com/Vectorized/solady/blob/b609a9c79ce541c2beca7a7d247665e7c93942a3/src/utils/FixedPointMathLib.sol
// Stripped comments
/// @dev Returns the square root of `x`, rounded down.
function sqrt(uint256 x) pure returns (uint256 z) {
    assembly ("memory-safe") {
        z := 181

        let r := shl(7, lt(0xffffffffffffffffffffffffffffffffff, x))
        r := or(r, shl(6, lt(0xffffffffffffffffff, shr(r, x))))
        r := or(r, shl(5, lt(0xffffffffff, shr(r, x))))
        r := or(r, shl(4, lt(0xffffff, shr(r, x))))
        z := shl(shr(1, r), z)

        z := shr(18, mul(z, add(shr(r, x), 65536)))

        z := shr(1, add(z, div(x, z)))
        z := shr(1, add(z, div(x, z)))
        z := shr(1, add(z, div(x, z)))
        z := shr(1, add(z, div(x, z)))
        z := shr(1, add(z, div(x, z)))
        z := shr(1, add(z, div(x, z)))
        z := shr(1, add(z, div(x, z)))

        z := sub(z, lt(div(x, z), z))
    }
}
