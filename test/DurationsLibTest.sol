// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Morpho Association
pragma solidity ^0.8.0;

import "../lib/forge-std/src/Test.sol";
// import {MorphoMarketV2Adapter, Maturity, ObligationPosition} from "../src/adapters/MorphoMarketV2Adapter.sol";
// import {MorphoMarketV2AdapterFactory} from "../src/adapters/MorphoMarketV2AdapterFactory.sol";
// import {ERC20Mock} from "./mocks/ERC20Mock.sol";
// import {OracleMock} from "../lib/morpho-blue/src/mocks/OracleMock.sol";
// import {VaultV2Mock} from "./mocks/VaultV2Mock.sol";
// import {IERC20} from "../src/interfaces/IERC20.sol";
// import {IVaultV2} from "../src/interfaces/IVaultV2.sol";
// import {IMorphoMarketV2Adapter} from "../src/adapters/interfaces/IMorphoMarketV2Adapter.sol";
// import {IMorphoMarketV2AdapterFactory} from "../src/adapters/interfaces/IMorphoMarketV2AdapterFactory.sol";
// import {MathLib} from "../src/libraries/MathLib.sol";
// import {MathLib as MorphoV2MathLib} from "lib/morpho-v2/src/libraries/MathLib.sol";
// import {MorphoV2} from "../lib/morpho-v2/src/MorphoV2.sol";
// import {Offer, Signature, Obligation, Collateral, Proof} from "../lib/morpho-v2/src/interfaces/IMorphoV2.sol";
// import {stdStorage, StdStorage} from "../lib/forge-std/src/Test.sol";
// import {stdError} from "../lib/forge-std/src/StdError.sol";
// import {ORACLE_PRICE_SCALE} from "../lib/morpho-blue/src/libraries/ConstantsLib.sol";
import {DurationsLib, MAX_DURATIONS} from "../src/adapters/libraries/DurationsLib.sol";

contract DurationsLibTest is Test {
    /// forge-config: default.allow_internal_expect_revert = true
    function testGetInvalidIndex(bytes32 durations, uint256 index) public {
        index = bound(index, MAX_DURATIONS, type(uint256).max);
        vm.expectRevert(DurationsLib.InvalidIndex.selector);
        DurationsLib.get(durations, index);
    }

    /// forge-config: default.allow_internal_expect_revert = true
    function testSetInvalidIndex(bytes32 durations, uint256 index, uint32 value) public {
        index = bound(index, MAX_DURATIONS, type(uint256).max);
        vm.expectRevert(DurationsLib.InvalidIndex.selector);
        DurationsLib.set(durations, index, value);
    }

    /// forge-config: default.allow_internal_expect_revert = true
    function testSetInvalidValue(bytes32 durations, uint256 index, uint256 value) public {
        value = bound(value, uint256(type(uint32).max) + 1, type(uint256).max);
        vm.expectRevert(DurationsLib.InvalidValue.selector);
        DurationsLib.set(durations, index, value);
    }

    function testGetValid(bytes32 durations, uint256 index) public pure {
        index = bound(index, 0, MAX_DURATIONS - 1);
        uint256 expectedValue = uint256(uint32(bytes4(durations << (32 * index))));
        assertEq(DurationsLib.get(durations, index), expectedValue);
    }

    function testSetValid(bytes32 durations, uint256 writtenIndex, uint256 value, uint256 readIndex) public pure {
        value = bound(value, 0, type(uint32).max);
        writtenIndex = bound(writtenIndex, 0, MAX_DURATIONS - 1);
        readIndex = bound(readIndex, 0, MAX_DURATIONS - 2);
        if (readIndex == writtenIndex) readIndex = MAX_DURATIONS - 1;

        uint256 readValue = DurationsLib.get(durations, readIndex);
        bytes32 newDurations = DurationsLib.set(durations, writtenIndex, value);
        assertEq(DurationsLib.get(newDurations, writtenIndex), value);
        assertEq(DurationsLib.get(newDurations, readIndex), readValue);
    }
}
