// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import {Test} from "../../lib/forge-std/src/Test.sol";
import {SymTest} from "../../lib/morpho-blue/lib/halmos-cheatcodes/src/SymTest.sol";

import {IVaultV2Factory} from "../../src/interfaces/IVaultV2Factory.sol";
import "../../src/interfaces/IVaultV2.sol";

import {VaultV2Factory} from "../../src/VaultV2Factory.sol";
import "../../src/VaultV2.sol";

import {ERC20Mock} from "../mocks/ERC20Mock.sol";

/// @custom:halmos --solver-timeout-assertion 0
contract VaultAccessControlHalmosTest is SymTest, Test {
    ERC20Mock internal underlyingToken;
    IVaultV2Factory internal vaultFactory;
    IVaultV2 vault;

    address internal owner;
    address internal curator;
    address internal sentinel;
    address internal allocator;

    bytes internal pendingAllocatorData;

    function setUp() public virtual {

        owner = svm.createAddress("owner");
        curator = svm.createAddress("curator");
        sentinel = svm.createAddress("sentinel");
        allocator = svm.createAddress("allocator");

        underlyingToken = new ERC20Mock(18);
        vm.label(address(underlyingToken), "underlying");

        //VaultV2 implementation = new VaultV2(owner, address(underlyingToken));
        vault = IVaultV2(address(new VaultV2(owner, address(underlyingToken))));

        vm.label(address(vault), "vault");
        vm.startPrank(owner);
        vault.setCurator(curator);
        vault.setIsSentinel(sentinel, true);
        vm.stopPrank();

        //pendingAllocatorData = abi.encodeCall(IVaultV2.setIsAllocator, (allocator, true));
        vm.prank(curator);
        vault.submit(pendingAllocatorData);

        svm.enableSymbolicStorage(address(this));
        svm.enableSymbolicStorage(address(vault));
        svm.enableSymbolicStorage(address(underlyingToken));

        deal(address(underlyingToken), address(this), type(uint256).max);

        vm.roll(svm.createUint(64, "block.number"));
        vm.warp(svm.createUint(64, "block.timestamp"));
    }

    function check_submitAccessControl(address caller) public {
        address candidateAllocator = svm.createAddress("candidateAllocator");
        bytes memory data = abi.encodeCall(IVaultV2.setIsAllocator, (candidateAllocator, true));

        vm.prank(caller);
        (bool success,) = address(vault).call(abi.encodeCall(IVaultV2.submit, (data)));

        assert(!success || caller == curator);
    }

    function check_revokeAccessControl(address caller) public {
        vm.prank(caller);
        (bool success,) = address(vault).call(abi.encodeCall(IVaultV2.revoke, (pendingAllocatorData)));

        assert(!success || caller == curator || caller == sentinel);
    }

    function check_setIsAllocator(address rdm) public {
        vm.assume(rdm != curator);
        address newAllocator = makeAddr("newAllocator");

        // Only curator can submit
        vm.expectRevert(ErrorsLib.Unauthorized.selector);
        vm.prank(rdm);
        (bool success, ) = address(vault).call(abi.encodeCall(vault.setIsAllocator, (newAllocator, true)));
        assert(!success);

        // Nobody can set directly
        vm.expectRevert(ErrorsLib.DataNotTimelocked.selector);
        vm.prank(rdm);
        vault.setIsAllocator(newAllocator, true);
        vm.expectRevert(ErrorsLib.DataNotTimelocked.selector);
        vm.prank(curator);
        vault.setIsAllocator(newAllocator, true);

        // Normal path
        vm.prank(curator);
        vault.submit(abi.encodeCall(IVaultV2.setIsAllocator, (newAllocator, true)));
        vm.expectEmit();
        emit EventsLib.SetIsAllocator(newAllocator, true);
        vault.setIsAllocator(newAllocator, true);
        assertTrue(vault.isAllocator(newAllocator));

        // Removal
        vm.prank(curator);
        vault.submit(abi.encodeCall(IVaultV2.setIsAllocator, (newAllocator, false)));
        vm.expectEmit();
        emit EventsLib.SetIsAllocator(newAllocator, false);
        vault.setIsAllocator(newAllocator, false);
        assertFalse(vault.isAllocator(newAllocator));
    }
}