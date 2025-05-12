// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import {IVaultV2Factory} from "../src/interfaces/IVaultV2Factory.sol";
import {IVaultV2, IERC20} from "../src/interfaces/IVaultV2.sol";
import {IManualVicFactory} from "../src/vic/interfaces/IManualVicFactory.sol";

import {VaultV2Factory} from "../src/VaultV2Factory.sol";
import {ManualVic, ManualVicFactory} from "../src/vic/ManualVicFactory.sol";
import "../src/VaultV2.sol";

import {ERC20Mock} from "./mocks/ERC20Mock.sol";

import {Test, console} from "../lib/forge-std/src/Test.sol";
import {stdError} from "forge-std/StdError.sol";

contract BaseTest is Test {
    address immutable owner = makeAddr("owner");
    address immutable curator = makeAddr("curator");
    address immutable allocator = makeAddr("allocator");
    address immutable sentinel = makeAddr("sentinel");

    ERC20Mock underlyingToken;
    IVaultV2Factory vaultFactory;
    IVaultV2 vault;
    IManualVicFactory vicFactory;
    ManualVic vic;

    bytes[] bundle;

    function setUp() public virtual {
        vm.label(address(this), "testContract");

        underlyingToken = new ERC20Mock();
        vm.label(address(underlyingToken), "underlying");

        vaultFactory = IVaultV2Factory(address(new VaultV2Factory()));

        vault = IVaultV2(vaultFactory.createVaultV2(owner, address(underlyingToken), bytes32(0)));
        vm.label(address(vault), "vault");
        vicFactory = IManualVicFactory(address(new ManualVicFactory()));
        vic = ManualVic(vicFactory.createManualVic(address(vault), bytes32(0)));
        vm.label(address(vic), "vic");

        vm.startPrank(owner);
        vault.setCurator(curator);
        vault.setIsSentinel(sentinel, true);
        vm.stopPrank();

        vm.startPrank(curator);
        ManualVic(vic).increaseMaxInterestPerSecond(type(uint256).max);
        vault.submit(abi.encodeWithSelector(IVaultV2.setIsAllocator.selector, allocator, true));
        vault.submit(abi.encodeWithSelector(IVaultV2.setVic.selector, address(vic)));
        vm.stopPrank();

        vault.setIsAllocator(allocator, true);
        vault.setVic(address(vic));
    }

    function bound96(uint96 x, uint96 _min, uint96 _max) public pure returns (uint96) {
        return uint96(bound(uint256(x), uint256(_min), uint256(_max)));
    }
}

function min(uint256 a, uint256 b) pure returns (uint256) {
    return a < b ? a : b;
}
