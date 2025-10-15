// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Morpho Association
pragma solidity ^0.8.0;

import {IVaultV2Factory} from "../src/interfaces/IVaultV2Factory.sol";
import "../src/interfaces/IVaultV2.sol";

import {VaultV2Factory} from "../src/VaultV2Factory.sol";
import "../src/VaultV2.sol";

import {ERC20Mock} from "./mocks/ERC20Mock.sol";
import {AdapterMock} from "./mocks/AdapterMock.sol";

import {Test, console} from "../lib/forge-std/src/Test.sol";
import {stdError} from "../lib/forge-std/src/StdError.sol";
import {TOTAL_ASSETS_AND_LAST_UPDATE_PACKED_SLOT} from "./PackingTest.sol";

contract BaseTest is Test {
    address immutable owner = makeAddr("owner");
    address immutable curator = makeAddr("curator");
    address immutable allocator = makeAddr("allocator");
    address immutable sentinel = makeAddr("sentinel");

    uint256 underlyingTokenDecimals;

    ERC20Mock underlyingToken;
    IVaultV2Factory vaultFactory;
    IVaultV2 vault;

    bytes[] bundle;
    bytes32[] expectedIds;
    bytes[] expectedIdData;

    function setUp() public virtual {
        vm.label(address(this), "testContract");

        underlyingTokenDecimals = vm.envOr("DECIMALS", uint256(18));
        require(underlyingTokenDecimals <= 36, "decimals too high");

        underlyingToken = new ERC20Mock(uint8(underlyingTokenDecimals));
        vm.label(address(underlyingToken), "underlying");

        vaultFactory = IVaultV2Factory(address(new VaultV2Factory()));

        vault = IVaultV2(vaultFactory.createVaultV2(owner, address(underlyingToken), bytes32(0)));
        vm.label(address(vault), "vault");

        vm.startPrank(owner);
        vault.setCurator(curator);
        vault.setIsSentinel(sentinel, true);
        vm.stopPrank();

        vm.prank(curator);
        vault.submit(abi.encodeCall(IVaultV2.setIsAllocator, (allocator, true)));
        vault.setIsAllocator(allocator, true);

        expectedIds = new bytes32[](2);
        expectedIds[0] = keccak256("id-0");
        expectedIds[1] = keccak256("id-1");

        expectedIdData = new bytes[](2);
        expectedIdData[0] = "id-0";
        expectedIdData[1] = "id-1";
    }

    function writeTotalAssets(uint256 newTotalAssets) internal {
        bytes32 value = vm.load(address(vault), TOTAL_ASSETS_AND_LAST_UPDATE_PACKED_SLOT);
        bytes32 strippedValue = (value >> 192) << 192;
        assertLe(newTotalAssets, type(uint192).max, "wrong written value");
        vm.store(address(vault), TOTAL_ASSETS_AND_LAST_UPDATE_PACKED_SLOT, strippedValue | bytes32(newTotalAssets));
        assertEq(vault._totalAssets(), newTotalAssets, "writeTotalAssets failed");
    }

    function increaseAbsoluteCap(bytes memory idData, uint256 absoluteCap) internal {
        vm.prank(curator);
        vault.submit(abi.encodeCall(IVaultV2.increaseAbsoluteCap, (idData, absoluteCap)));
        vault.increaseAbsoluteCap(idData, absoluteCap);
        assertEq(vault.absoluteCap(keccak256(idData)), absoluteCap);
    }

    function increaseRelativeCap(bytes memory idData, uint256 relativeCap) internal {
        vm.prank(curator);
        vault.submit(abi.encodeCall(IVaultV2.increaseRelativeCap, (idData, relativeCap)));
        vault.increaseRelativeCap(idData, relativeCap);
        assertEq(vault.relativeCap(keccak256(idData)), relativeCap);
    }
}

function min(uint256 a, uint256 b) pure returns (uint256) {
    return a < b ? a : b;
}
