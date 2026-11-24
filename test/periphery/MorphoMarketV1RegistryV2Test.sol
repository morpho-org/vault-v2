// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Morpho Association
pragma solidity ^0.8.0;

import {Test} from "../../lib/forge-std/src/Test.sol";
import {IMorphoMarketV1AdapterV2Factory} from "../../src/adapters/interfaces/IMorphoMarketV1AdapterV2Factory.sol";
import {MorphoMarketV1RegistryV2} from "../../src/periphery/registries/MorphoMarketV1RegistryV2.sol";
import {IMorphoMarketV1RegistryV2} from "../../src/periphery/registries/interfaces/IMorphoMarketV1RegistryV2.sol";

contract MorphoMarketV1RegistryV2Test is Test {
    IMorphoMarketV1RegistryV2 registry;
    address morphoMarketV1AdapterV2Factory = address(0x1001);

    function setUp() public {
        registry = new MorphoMarketV1RegistryV2(morphoMarketV1AdapterV2Factory);
    }

    function testConstructor() public view {
        assertEq(registry.morphoMarketV1AdapterV2Factory(), morphoMarketV1AdapterV2Factory);
    }

    function testIsInRegistry(address adapter, bool isMorphoMarketV1AdapterV2) public {
        vm.mockCall(
            morphoMarketV1AdapterV2Factory,
            abi.encodeCall(IMorphoMarketV1AdapterV2Factory.isMorphoMarketV1AdapterV2, (adapter)),
            abi.encode(isMorphoMarketV1AdapterV2)
        );

        assertEq(registry.isInRegistry(adapter), isMorphoMarketV1AdapterV2);
    }
}
