// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import "forge-std/Test.sol";

import {ERC20Mock} from "./mocks/ERC20Mock.sol";
import {ERC4626Mock} from "./mocks/ERC4626Mock.sol";
import {ERC4626Adapter, ERC4626AdapterFactory} from "src/adapters/ERC4626Adapter.sol";

/// @notice Minimal stub contract used as the parent vault by the ERC4626Adapter in tests.
contract VaultStub {
    address public asset;

    constructor(address _asset) {
        asset = _asset;
    }
}

contract ERC4626AdapterTest is Test {
    ERC20Mock internal asset;
    ERC4626Mock internal erc4626Vault;
    VaultStub internal parentVault;
    ERC4626AdapterFactory internal factory;
    ERC4626Adapter internal adapter;

    uint256 internal constant MIN_TEST_AMOUNT = 1e6;
    uint256 internal constant MAX_TEST_AMOUNT = 1e24;

    function setUp() public {
        asset = new ERC20Mock();
        erc4626Vault = new ERC4626Mock(address(asset));
        parentVault = new VaultStub(address(asset));

        factory = new ERC4626AdapterFactory();
        adapter = ERC4626Adapter(factory.createERC4626Adapter(address(parentVault)));
    }

    function _boundAmount(uint256 amount) internal pure returns (uint256) {
        return bound(amount, MIN_TEST_AMOUNT, MAX_TEST_AMOUNT);
    }

    function testParentVaultAndAssetSet() public {
        assertEq(adapter.parentVault(), address(parentVault), "Incorrect parent vault set");
        assertEq(adapter.asset(), address(asset), "Incorrect asset set");
    }

    function testAllocateInNotAuthorizedReverts(uint256 amount) public {
        amount = _boundAmount(amount);
        vm.expectRevert(bytes("not authorized"));
        adapter.allocateIn(abi.encode(address(erc4626Vault)), amount);
    }

    function testAllocateOutNotAuthorizedReverts(uint256 amount) public {
        amount = _boundAmount(amount);
        vm.expectRevert(bytes("not authorized"));
        adapter.allocateOut(abi.encode(address(erc4626Vault)), amount);
    }

    function testAllocateInDepositsAssetsToERC4626Vault(uint256 amount) public {
        amount = _boundAmount(amount);
        deal(address(asset), address(adapter), amount);

        vm.prank(address(parentVault));
        bytes32[] memory ids = adapter.allocateIn(abi.encode(address(erc4626Vault)), amount);

        uint256 adapterShares = erc4626Vault.balanceOf(address(adapter));
        assertEq(adapterShares, amount, "Incorrect share balance after deposit");
        assertEq(asset.balanceOf(address(adapter)), 0, "Underlying tokens not transferred to vault");

        bytes32 expectedId = keccak256(abi.encode("vault", address(erc4626Vault)));
        assertEq(ids.length, 1, "Unexpected number of ids returned");
        assertEq(ids[0], expectedId, "Incorrect id returned");
    }

    function testAllocateOutWithdrawsAssetsFromERC4626Vault(uint256 initialAmount, uint256 withdrawRatio) public {
        initialAmount = _boundAmount(initialAmount);
        withdrawRatio = bound(withdrawRatio, 1, 100);

        uint256 withdrawAmount = (initialAmount * withdrawRatio) / 100;

        deal(address(asset), address(adapter), initialAmount);
        vm.prank(address(parentVault));
        adapter.allocateIn(abi.encode(address(erc4626Vault)), initialAmount);

        uint256 beforeShares = erc4626Vault.balanceOf(address(adapter));
        assertEq(beforeShares, initialAmount, "Precondition failed: shares not set");

        vm.prank(address(parentVault));
        bytes32[] memory ids = adapter.allocateOut(abi.encode(address(erc4626Vault)), withdrawAmount);

        uint256 afterShares = erc4626Vault.balanceOf(address(adapter));
        assertEq(afterShares, initialAmount - withdrawAmount, "Share balance not decreased correctly");

        uint256 adapterBalance = asset.balanceOf(address(adapter));
        assertEq(adapterBalance, withdrawAmount, "Adapter did not receive withdrawn tokens");

        bytes32 expectedId = keccak256(abi.encode("vault", address(erc4626Vault)));
        assertEq(ids.length, 1, "Unexpected number of ids returned");
        assertEq(ids[0], expectedId, "Incorrect id returned");
    }

    function testFactoryCreateAdapter() public {
        VaultStub parentVault = new VaultStub(address(asset));

        bytes32 initCodeHash =
            keccak256(abi.encodePacked(type(ERC4626Adapter).creationCode, abi.encode(address(parentVault))));
        address expectedNewAdapter =
            address(uint160(uint256(keccak256(abi.encodePacked(uint8(0xff), factory, bytes32(0), initCodeHash)))));
        vm.expectEmit();
        emit ERC4626AdapterFactory.CreateERC4626Adapter(address(parentVault), expectedNewAdapter);

        address newAdapter = factory.createERC4626Adapter(address(parentVault));

        assertTrue(newAdapter != address(0), "Adapter not created");
        assertEq(ERC4626Adapter(newAdapter).parentVault(), address(parentVault), "Incorrect parent vault");
        assertEq(ERC4626Adapter(newAdapter).asset(), address(asset), "Incorrect asset");
        assertEq(factory.adapter(address(parentVault)), newAdapter, "Adapter not tracked correctly");
    }
}
