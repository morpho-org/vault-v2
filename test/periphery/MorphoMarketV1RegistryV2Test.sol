// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Morpho Association
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";
import {MorphoMarketV1RegistryV2} from "../../src/periphery/registries/MorphoMarketV1RegistryV2.sol";
import {IMorphoMarketV1RegistryV2} from "../../src/periphery/registries/interfaces/IMorphoMarketV1RegistryV2.sol";

contract MorphoMarketV1RegistryV2Test is Test {
    IMorphoMarketV1RegistryV2 registry;
    address morphoMarketV1AdapterV2Factory = address(0x1001);

    function setUp() public {
        registry = IMorphoMarketV1RegistryV2(address(new MorphoMarketV1RegistryV2(morphoMarketV1AdapterV2Factory)));
    }

    function testConstructor() public view {
        assertEq(registry.morphoMarketV1AdapterV2Factory(), morphoMarketV1AdapterV2Factory);
    }

    function testIsInRegistry(address adapter, bool isMorphoMarketV1AdapterV2) public {
        vm.assume(adapter != address(vm));
        vm.mockCall(
            morphoMarketV1AdapterV2Factory,
            abi.encodeWithSignature("isMorphoMarketV1AdapterV2(address)", adapter),
            abi.encode(isMorphoMarketV1AdapterV2)
        );

        assertEq(registry.isInRegistry(adapter), isMorphoMarketV1AdapterV2);
    }
}
