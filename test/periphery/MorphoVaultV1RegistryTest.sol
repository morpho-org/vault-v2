// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Morpho Association
pragma solidity ^0.8.28;

import {Test} from "../../lib/forge-std/src/Test.sol";
import {MorphoVaultV1Registry} from "../../src/periphery/registries/MorphoVaultV1Registry.sol";
import {IMorphoVaultV1Registry} from "../../src/periphery/registries/interfaces/IMorphoVaultV1Registry.sol";

contract MorphoVaultV1RegistryTest is Test {
    IMorphoVaultV1Registry registry;
    address morphoVaultV1Factory = address(0x1001);
    address morphoVaultV1AdapterFactory = address(0x1002);

    function setUp() public {
        registry = IMorphoVaultV1Registry(
            address(new MorphoVaultV1Registry(morphoVaultV1AdapterFactory, morphoVaultV1Factory))
        );
    }

    function testConstructor() public view {
        assertEq(registry.morphoVaultV1AdapterFactory(), morphoVaultV1AdapterFactory);
        assertEq(registry.morphoVaultV1Factory(), morphoVaultV1Factory);
    }

    function testIsInRegistry(address adapter, address morphoVaultV1, bool isMorphoVaultV1Adapter, bool isMetaMorpho)
        public
    {
        vm.assume(adapter != address(vm));
        vm.mockCall(
            morphoVaultV1AdapterFactory,
            abi.encodeWithSignature("isMorphoVaultV1Adapter(address)", adapter),
            abi.encode(isMorphoVaultV1Adapter)
        );

        if (isMorphoVaultV1Adapter) {
            vm.mockCall(adapter, abi.encodeWithSignature("morphoVaultV1()"), abi.encode(morphoVaultV1));
            vm.mockCall(
                morphoVaultV1Factory,
                abi.encodeWithSignature("isMetaMorpho(address)", morphoVaultV1),
                abi.encode(isMetaMorpho)
            );
        }

        bool expected = isMorphoVaultV1Adapter && isMetaMorpho;
        assertEq(registry.isInRegistry(adapter), expected);
    }

    // check that if the adapter isn't a vault adapter, it doesn't revert (basically checks the order of execution of
    // solidity).
    function testNoObscureRevert(address adapter) public {
        vm.mockCall(
            morphoVaultV1AdapterFactory,
            abi.encodeWithSignature("isMorphoVaultV1Adapter(address)", adapter),
            abi.encode(false)
        );

        registry.isInRegistry(adapter);
    }
}
