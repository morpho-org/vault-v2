// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import {IVaultV2Factory} from "../src/interfaces/IVaultV2Factory.sol";
import {IVaultV2, IERC20} from "../src/interfaces/IVaultV2.sol";

import {VaultV2Factory} from "../src/VaultV2Factory.sol";
import "../src/VaultV2.sol";
import {ManualInterestController} from "../src/interest-controllers/ManualInterestController.sol";

import {ERC20Mock} from "./mocks/ERC20Mock.sol";

import {Test, console} from "../lib/forge-std/src/Test.sol";
import {stdError} from "forge-std/StdError.sol";

contract BaseTest is Test {
    address immutable manager = makeAddr("manager");
    address immutable owner = makeAddr("owner");
    address immutable curator = makeAddr("curator");
    address immutable allocator = makeAddr("allocator");
    address immutable sentinel = makeAddr("sentinel");

    ERC20Mock underlyingToken;
    IVaultV2Factory vaultFactory;
    IVaultV2 vault;
    ManualInterestController interestController;

    bytes[] bundle;

    function setUp() public virtual {
        vm.label(address(this), "testContract");

        underlyingToken = new ERC20Mock();
        vm.label(address(underlyingToken), "underlying");

        vaultFactory = IVaultV2Factory(address(new VaultV2Factory()));

        vault = IVaultV2(vaultFactory.createVaultV2(owner, address(underlyingToken), bytes32(0)));
        vm.label(address(vault), "vault");
        interestController = new ManualInterestController(manager);
        vm.label(address(interestController), "InterestController");

        vm.startPrank(owner);
        vault.setCurator(curator);
        vault.setIsSentinel(sentinel, true);
        vm.stopPrank();

        vm.startPrank(curator);
        vault.submit(abi.encodeWithSelector(IVaultV2.setIsAllocator.selector, allocator, true));
        vault.submit(abi.encodeWithSelector(IVaultV2.setInterestController.selector, address(interestController)));
        vm.stopPrank();

        vault.setIsAllocator(allocator, true);
        vault.setInterestController(address(interestController));
    }
}

function min(uint256 a, uint256 b) pure returns (uint256) {
    return a < b ? a : b;
}
