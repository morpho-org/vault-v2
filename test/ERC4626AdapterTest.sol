// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import "forge-std/Test.sol";

import {IERC4626} from "src/interfaces/IERC4626.sol";
import {ERC20Mock} from "./mocks/ERC20Mock.sol";
import {ERC4626Mock} from "./mocks/ERC4626Mock.sol";
import {ERC4626Adapter} from "src/adapters/ERC4626Adapter.sol";
import {ERC4626AdapterFactory} from "src/adapters/ERC4626AdapterFactory.sol";
import {VaultV2Mock} from "./mocks/VaultV2Mock.sol";
import {IERC20} from "src/interfaces/IERC20.sol";
import {IVaultV2} from "src/interfaces/IVaultV2.sol";

contract ERC4626AdapterTest is Test {
    ERC20Mock internal asset;
    ERC20Mock internal rewardToken;
    VaultV2Mock internal parentVault;
    ERC4626Mock internal vault;
    ERC4626AdapterFactory internal factory;
    ERC4626Adapter internal adapter;
    address internal owner;
    address internal recipient;

    uint256 internal constant MAX_TEST_ASSETS = 1e36;

    function setUp() public {
        owner = makeAddr("owner");
        recipient = makeAddr("recipient");

        asset = new ERC20Mock();
        rewardToken = new ERC20Mock();
        vault = new ERC4626Mock(address(asset));
        parentVault = new VaultV2Mock(address(asset), owner, address(0), address(0), address(0));

        factory = new ERC4626AdapterFactory();
        adapter = ERC4626Adapter(factory.createERC4626Adapter(address(parentVault), address(vault)));
    }

    function testParentVaultAndAssetSet() public view {
        assertEq(adapter.parentVault(), address(parentVault), "Incorrect parent vault set");
        assertEq(adapter.vault(), address(vault), "Incorrect vault set");
    }

    function testAllocateNotAuthorizedReverts(uint256 assets) public {
        assets = bound(assets, 0, MAX_TEST_ASSETS);
        vm.expectRevert(ERC4626Adapter.NotAuthorized.selector);
        adapter.allocate(hex"", assets);
    }

    function testDeallocateNotAuthorizedReverts(uint256 assets) public {
        assets = bound(assets, 0, MAX_TEST_ASSETS);
        vm.expectRevert(ERC4626Adapter.NotAuthorized.selector);
        adapter.deallocate(hex"", assets);
    }

    function testAllocateDepositsAssetsToERC4626Vault(uint256 assets) public {
        assets = bound(assets, 0, MAX_TEST_ASSETS);
        deal(address(asset), address(adapter), assets);

        vm.prank(address(parentVault));
        bytes32[] memory ids = adapter.allocate(hex"", assets);

        uint256 adapterShares = vault.balanceOf(address(adapter));
        // In general this should not hold (having as many shares as assets). TODO: fix.
        assertEq(adapterShares, assets, "Incorrect share balance after deposit");
        assertEq(asset.balanceOf(address(adapter)), 0, "Underlying tokens not transferred to vault");

        bytes32 expectedId = keccak256(abi.encode("adapter", address(adapter)));
        assertEq(ids.length, 1, "Unexpected number of ids returned");
        assertEq(ids[0], expectedId, "Incorrect id returned");
    }

    function testDeallocateWithdrawsAssetsFromERC4626Vault(uint256 initialAssets, uint256 withdrawAssets) public {
        initialAssets = bound(initialAssets, 0, MAX_TEST_ASSETS);
        withdrawAssets = bound(withdrawAssets, 0, initialAssets);

        deal(address(asset), address(adapter), initialAssets);
        vm.prank(address(parentVault));
        adapter.allocate(hex"", initialAssets);

        uint256 beforeShares = vault.balanceOf(address(adapter));
        // In general this should not hold (having as many shares as assets). TODO: fix.
        assertEq(beforeShares, initialAssets, "Precondition failed: shares not set");

        vm.prank(address(parentVault));
        bytes32[] memory ids = adapter.deallocate(hex"", withdrawAssets);

        uint256 afterShares = vault.balanceOf(address(adapter));
        assertEq(afterShares, initialAssets - withdrawAssets, "Share balance not decreased correctly");

        uint256 adapterBalance = asset.balanceOf(address(adapter));
        assertEq(adapterBalance, withdrawAssets, "Adapter did not receive withdrawn tokens");

        bytes32 expectedId = keccak256(abi.encode("adapter", address(adapter)));
        assertEq(ids.length, 1, "Unexpected number of ids returned");
        assertEq(ids[0], expectedId, "Incorrect id returned");
    }

    function testFactoryCreateAdapter() public {
        VaultV2Mock newParentVault = new VaultV2Mock(address(asset), owner, address(0), address(0), address(0));
        ERC4626Mock newVault = new ERC4626Mock(address(asset));

        bytes32 initCodeHash = keccak256(
            abi.encodePacked(type(ERC4626Adapter).creationCode, abi.encode(address(newParentVault), address(newVault)))
        );
        address expectedNewAdapter =
            address(uint160(uint256(keccak256(abi.encodePacked(uint8(0xff), factory, bytes32(0), initCodeHash)))));
        vm.expectEmit();
        emit ERC4626AdapterFactory.CreateERC4626Adapter(address(newParentVault), address(newVault), expectedNewAdapter);

        address newAdapter = factory.createERC4626Adapter(address(newParentVault), address(newVault));

        assertTrue(newAdapter != address(0), "Adapter not created");
        assertEq(ERC4626Adapter(newAdapter).parentVault(), address(newParentVault), "Incorrect parent vault");
        assertEq(ERC4626Adapter(newAdapter).vault(), address(newVault), "Incorrect vault");
        assertEq(
            factory.adapter(address(newParentVault), address(newVault)), newAdapter, "Adapter not tracked correctly"
        );
        assertTrue(factory.isAdapter(newAdapter), "Adapter not tracked correctly");
    }

    function testSetSkimRecipient(address newRecipient, address caller) public {
        vm.assume(newRecipient != address(0));
        vm.assume(caller != address(0));
        vm.assume(caller != owner);

        // Access control
        vm.prank(caller);
        vm.expectRevert(ERC4626Adapter.NotAuthorized.selector);
        adapter.setSkimRecipient(newRecipient);

        // Normal path
        vm.prank(owner);
        vm.expectEmit();
        emit ERC4626Adapter.SetSkimRecipient(newRecipient);
        adapter.setSkimRecipient(newRecipient);
        assertEq(adapter.skimRecipient(), newRecipient, "Skim recipient not set correctly");
    }

    function testSkim(uint256 assets) public {
        assets = bound(assets, 0, MAX_TEST_ASSETS);

        ERC20Mock token = new ERC20Mock();

        // Setup
        vm.prank(owner);
        adapter.setSkimRecipient(recipient);
        deal(address(token), address(adapter), assets);
        assertEq(token.balanceOf(address(adapter)), assets, "Adapter did not receive tokens");

        // Normal path
        vm.expectEmit();
        emit ERC4626Adapter.Skim(address(token), assets);
        vm.prank(recipient);
        adapter.skim(address(token));
        assertEq(token.balanceOf(address(adapter)), 0, "Tokens not skimmed from adapter");
        assertEq(token.balanceOf(recipient), assets, "Recipient did not receive tokens");

        // Access control
        vm.expectRevert(ERC4626Adapter.NotAuthorized.selector);
        adapter.skim(address(token));

        // Cant skim vault
        vm.expectRevert(ERC4626Adapter.CannotSkimVault.selector);
        vm.prank(recipient);
        adapter.skim(address(vault));
    }

    function testRealiseLossNotAuthorizedReverts() public {
        vm.expectRevert(ERC4626Adapter.NotAuthorized.selector);
        adapter.realiseLoss(hex"");
    }

    function testLossRealization(uint256 initialAssets, uint256 lossAssets) public {
        initialAssets = bound(initialAssets, 0, MAX_TEST_ASSETS);
        lossAssets = bound(lossAssets, 0, initialAssets);

        // Setup.
        deal(address(asset), address(adapter), initialAssets);
        vm.prank(address(parentVault));
        adapter.allocate(hex"", initialAssets);

        // Loss detection.
        vm.mockCall(
            address(vault),
            abi.encodeWithSelector(IERC4626.previewRedeem.selector, initialAssets),
            abi.encode(initialAssets - lossAssets)
        );
        uint256 snapshot = vm.snapshot();
        vm.prank(address(parentVault));
        adapter.allocate(hex"", 0);
        assertEq(adapter.assetsInVaultIfNoLoss(), initialAssets, "Assets in vault should be tracked");
        vm.revertTo(snapshot);
        vm.prank(address(parentVault));
        adapter.deallocate(hex"", 0);
        assertEq(adapter.assetsInVaultIfNoLoss(), initialAssets, "Assets in vault should be tracked");

        // Realisation.
        vm.prank(address(parentVault));
        (uint256 realizedLoss, bytes32[] memory ids) = adapter.realiseLoss(hex"");
        assertEq(realizedLoss, lossAssets, "Realized loss should match expected loss");
        assertEq(adapter.assetsInVaultIfNoLoss(), initialAssets - realizedLoss, "Assets in vault should be tracked");
        assertEq(ids.length, 1, "Unexpected number of ids returned");
        assertEq(ids[0], keccak256(abi.encode("adapter", address(adapter))), "Incorrect id returned");

        // Can't realise loss twice.
        vm.prank(address(parentVault));
        (uint256 secondRealizedLoss, bytes32[] memory secondIds) = adapter.realiseLoss(hex"");
        assertEq(secondRealizedLoss, 0, "Second realized loss should be zero");
        assertEq(secondIds.length, 1, "Unexpected number of ids returned");
        assertEq(secondIds[0], keccak256(abi.encode("adapter", address(adapter))), "Incorrect id returned");
    }

    function testCumulativeLossRealization(
        uint256 initialAssets,
        uint256 firstLoss,
        uint256 secondLoss,
        uint256 depositAssets,
        uint256 withdrawAssets
    ) public {
        initialAssets = bound(initialAssets, 0, MAX_TEST_ASSETS);
        firstLoss = bound(firstLoss, 0, initialAssets);
        secondLoss = bound(secondLoss, 0, initialAssets - firstLoss);
        depositAssets = bound(depositAssets, 0, MAX_TEST_ASSETS);
        withdrawAssets = bound(withdrawAssets, 0, depositAssets);

        deal(address(asset), address(adapter), initialAssets + depositAssets);
        vm.prank(address(parentVault));
        adapter.allocate(hex"", initialAssets);

        // First loss
        vm.mockCall(
            address(vault),
            abi.encodeWithSelector(IERC4626.previewRedeem.selector, initialAssets),
            abi.encode(initialAssets - firstLoss)
        );
        vm.prank(address(parentVault));
        adapter.allocate(hex"", 0);
        assertEq(adapter.assetsInVaultIfNoLoss(), initialAssets, "Assets in vault should be tracked");

        // Second loss
        vm.mockCall(
            address(vault),
            abi.encodeWithSelector(IERC4626.previewRedeem.selector, initialAssets),
            abi.encode(initialAssets - firstLoss - secondLoss)
        );
        vm.prank(address(parentVault));
        adapter.allocate(hex"", 0);
        assertEq(adapter.assetsInVaultIfNoLoss(), initialAssets, "Assets in vault should be tracked");

        // Depositing doesn't change the loss.
        vm.prank(address(parentVault));
        adapter.allocate(hex"", depositAssets);
        assertEq(adapter.assetsInVaultIfNoLoss(), initialAssets + depositAssets, "Assets in vault should be tracked");

        // Withdrawing doesn't change the loss.
        vm.prank(address(parentVault));
        adapter.deallocate(hex"", withdrawAssets);
        assertEq(
            adapter.assetsInVaultIfNoLoss(),
            initialAssets + depositAssets - withdrawAssets,
            "Assets in vault should be tracked"
        );

        // Realise loss
        vm.prank(address(parentVault));
        (uint256 realizedLoss, bytes32[] memory ids) = adapter.realiseLoss(hex"");
        assertEq(realizedLoss, firstLoss + secondLoss, "Should realize the full cumulative loss");
        assertEq(
            adapter.assetsInVaultIfNoLoss(),
            initialAssets + depositAssets - withdrawAssets - realizedLoss,
            "Assets in vault should be tracked"
        );
        assertEq(ids.length, 1, "Unexpected number of ids returned");
    }

    function testInvalidData(bytes memory data) public {
        vm.assume(data.length > 0);

        vm.expectRevert(ERC4626Adapter.InvalidData.selector);
        adapter.allocate(data, 0);

        vm.expectRevert(ERC4626Adapter.InvalidData.selector);
        adapter.deallocate(data, 0);
    }
}
