// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import {IMetaMorphoFactory, IMetaMorpho} from "../lib/metamorpho/src/interfaces/IMetaMorphoFactory.sol";
import {IVaultV2Factory} from "../src/interfaces/IVaultV2Factory.sol";
import {IVaultV2, IERC20} from "../src/interfaces/IVaultV2.sol";
import {IManualVicFactory} from "../src/vic/interfaces/IManualVicFactory.sol";

import {VaultV2Factory} from "../src/VaultV2Factory.sol";
import {ManualVic, ManualVicFactory} from "../src/vic/ManualVicFactory.sol";
import "../src/VaultV2.sol";

import {ERC20Mock} from "./mocks/ERC20Mock.sol";

import {Test, console} from "../lib/forge-std/src/Test.sol";
import {stdError} from "../lib/forge-std/src/StdError.sol";

contract MockMetaMorphoFactory is IMetaMorphoFactory {
    address public immutable MORPHO;

    constructor(address morpho) {
        MORPHO = morpho;
    }

    function isMetaMorpho(address) external pure returns (bool) {
        return true;
    }

    /// @inheritdoc IMetaMorphoFactory
    function createMetaMorpho(address, uint256, address, string memory, string memory, bytes32)
        external
        pure
        returns (IMetaMorpho metaMorpho)
    {}
}

contract MockAdapterFactory is IAdapterFactory {
    function isAdapter(address) external pure returns (bool) {
        return true;
    }
}

contract BaseTest is Test {
    address immutable owner = makeAddr("owner");
    address immutable curator = makeAddr("curator");
    address immutable allocator = makeAddr("allocator");
    address immutable sentinel = makeAddr("sentinel");

    // The packed slot containing both _totalAssets and lastUpdate.
    bytes32 TOTAL_ASSETS_AND_LAST_UPDATE_PACKED_SLOT = bytes32(uint256(10));

    ERC20Mock underlyingToken;
    IVaultV2Factory vaultFactory;
    IVaultV2 vault;
    IManualVicFactory vicFactory;
    ManualVic vic;

    address adapterFactory;

    bytes[] bundle;

    function setUp() public virtual {
        adapterFactory = address(new MockAdapterFactory());

        vm.label(address(this), "testContract");

        underlyingToken = new ERC20Mock();
        vm.label(address(underlyingToken), "underlying");

        vaultFactory = IVaultV2Factory(address(new VaultV2Factory()));

        vault = IVaultV2(vaultFactory.createVaultV2(owner, address(underlyingToken), bytes32(0)));
        vm.label(address(vault), "vault");
        vicFactory = IManualVicFactory(address(new ManualVicFactory()));
        vic = ManualVic(vicFactory.createManualVic(address(vault)));
        vm.label(address(vic), "vic");

        vm.startPrank(owner);
        vault.setCurator(curator);
        vault.setIsSentinel(sentinel, true);
        vm.stopPrank();

        vm.prank(curator);
        vault.submit(abi.encodeCall(IVaultV2.setIsAdapterFactory, (adapterFactory, true)));
        vault.setIsAdapterFactory(adapterFactory, true);

        vm.startPrank(curator);
        ManualVic(vic).increaseMaxInterestPerSecond(type(uint256).max);
        vault.submit(abi.encodeCall(IVaultV2.setIsAllocator, (allocator, true)));
        vault.submit(abi.encodeCall(IVaultV2.setVic, (address(vic))));
        vm.stopPrank();

        vault.setIsAllocator(allocator, true);
        vault.setVic(address(vic));
    }

    function writeTotalAssets(uint256 newTotalAssets) internal {
        bytes32 value = vm.load(address(vault), TOTAL_ASSETS_AND_LAST_UPDATE_PACKED_SLOT);
        bytes32 strippedValue = (value >> 192) << 192;
        assertLe(newTotalAssets, type(uint192).max, "wrong written value");
        vm.store(address(vault), TOTAL_ASSETS_AND_LAST_UPDATE_PACKED_SLOT, strippedValue | bytes32(newTotalAssets));
    }
}

function min(uint256 a, uint256 b) pure returns (uint256) {
    return a < b ? a : b;
}
