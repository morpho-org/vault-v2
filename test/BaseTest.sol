// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import {IVaultV2Factory} from "../src/interfaces/IVaultV2Factory.sol";
import {IVaultV2, IERC20} from "../src/interfaces/IVaultV2.sol";

import {VaultV2Factory} from "../src/VaultV2Factory.sol";
import "../src/VaultV2.sol";
import {IRM} from "../src/IRM.sol";

import {ERC20Mock} from "./mocks/ERC20Mock.sol";

import {Test, console} from "../lib/forge-std/src/Test.sol";

contract BaseTest is Test {
    address immutable manager = makeAddr("manager");
    address immutable owner = makeAddr("owner");
    address immutable curator = makeAddr("curator");
    address immutable allocator = makeAddr("allocator");

    ERC20Mock underlyingToken;
    IVaultV2Factory vaultFactory;
    IVaultV2 vault;
    IRM irm;

    bytes[] bundle;

    function setUp() public virtual {
        vm.label(address(this), "testContract");

        underlyingToken = new ERC20Mock("UnderlyingToken", "UND");
        vm.label(address(underlyingToken), "underlying");

        vaultFactory = IVaultV2Factory(address(new VaultV2Factory()));

        vault = IVaultV2(vaultFactory.createVaultV2(owner, address(underlyingToken), bytes32(0)));
        vm.label(address(vault), "vault");
        irm = new IRM(manager);
        vm.label(address(irm), "IRM");

        vm.prank(owner);
        vault.setCurator(curator);

        vm.startPrank(curator);
        vault.submit(abi.encodeWithSelector(IVaultV2.setIsAllocator.selector, allocator, true));
        vault.submit(abi.encodeWithSelector(IVaultV2.setIRM.selector, address(irm)));
        vm.stopPrank();

        vault.setIsAllocator(allocator, true);
        vault.setIRM(address(irm));
    }
}

function min(uint256 a, uint256 b) pure returns (uint256) {
    return a < b ? a : b;
}
