// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import "forge-std/Test.sol";

import {IERC4626} from "src/interfaces/IERC4626.sol";
import {ERC20Mock} from "./mocks/ERC20Mock.sol";
import {ERC4626Mock} from "./mocks/ERC4626Mock.sol";
import {ERC4626Adapter} from "src/adapters/ERC4626Adapter.sol";
import {ERC4626AdapterFactory} from "src/adapters/ERC4626AdapterFactory.sol";
import {VaultMock} from "./mocks/VaultV2Mock.sol";
import {IERC20} from "src/interfaces/IERC20.sol";
import {IVaultV2} from "src/interfaces/IVaultV2.sol";

contract ERC4626AdapterTest is Test {
    ERC20Mock internal asset;
    ERC20Mock internal rewardToken;
    VaultMock internal parentVault;
    ERC4626Mock internal vault;
    ERC4626AdapterFactory internal factory;
    ERC4626Adapter internal adapter;
    address internal owner;
    address internal recipient;

    uint256 internal constant MIN_TEST_AMOUNT = 1e6;
    uint256 internal constant MAX_TEST_AMOUNT = 1e24;

    function setUp() public {
        owner = makeAddr("owner");
        recipient = makeAddr("recipient");

        asset = new ERC20Mock();
        rewardToken = new ERC20Mock();
        vault = new ERC4626Mock(address(asset));
        parentVault = new VaultMock(address(asset), owner);

        factory = new ERC4626AdapterFactory();
        adapter = ERC4626Adapter(factory.createERC4626Adapter(address(parentVault), address(vault)));
    }

    function _boundAmount(uint256 amount) internal pure returns (uint256) {
        return bound(amount, MIN_TEST_AMOUNT, MAX_TEST_AMOUNT);
    }

    function testParentVaultAndAssetSet() public view {
        assertEq(adapter.parentVault(), address(parentVault), "Incorrect parent vault set");
        assertEq(adapter.vault(), address(vault), "Incorrect vault set");
    }

    function testAllocateInNotAuthorizedReverts(uint256 amount) public {
        amount = _boundAmount(amount);
        vm.expectRevert(ERC4626Adapter.NotAuthorized.selector);
        adapter.allocateIn(hex"", amount);
    }

    function testAllocateOutNotAuthorizedReverts(uint256 amount) public {
        amount = _boundAmount(amount);
        vm.expectRevert(ERC4626Adapter.NotAuthorized.selector);
        adapter.allocateOut(hex"", amount);
    }

    function testAllocateInDepositsAssetsToERC4626Vault(uint256 amount) public {
        amount = _boundAmount(amount);
        deal(address(asset), address(adapter), amount);

        vm.prank(address(parentVault));
        bytes32[] memory ids = adapter.allocateIn(hex"", amount);

        uint256 adapterShares = vault.balanceOf(address(adapter));
        // In general this should not hold (having as many shares as assets). TODO: fix.
        assertEq(adapterShares, amount, "Incorrect share balance after deposit");
        assertEq(asset.balanceOf(address(adapter)), 0, "Underlying tokens not transferred to vault");

        bytes32 expectedId = keccak256(abi.encode("vault", address(vault)));
        assertEq(ids.length, 1, "Unexpected number of ids returned");
        assertEq(ids[0], expectedId, "Incorrect id returned");
    }

    function testAllocateOutWithdrawsAssetsFromERC4626Vault(uint256 initialAmount, uint256 withdrawAmount) public {
        initialAmount = _boundAmount(initialAmount);
        withdrawAmount = bound(withdrawAmount, 0, initialAmount);

        deal(address(asset), address(adapter), initialAmount);
        vm.prank(address(parentVault));
        adapter.allocateIn(hex"", initialAmount);

        uint256 beforeShares = vault.balanceOf(address(adapter));
        // In general this should not hold (having as many shares as assets). TODO: fix.
        assertEq(beforeShares, initialAmount, "Precondition failed: shares not set");

        vm.prank(address(parentVault));
        bytes32[] memory ids = adapter.allocateOut(hex"", withdrawAmount);

        uint256 afterShares = vault.balanceOf(address(adapter));
        assertEq(afterShares, initialAmount - withdrawAmount, "Share balance not decreased correctly");

        uint256 adapterBalance = asset.balanceOf(address(adapter));
        assertEq(adapterBalance, withdrawAmount, "Adapter did not receive withdrawn tokens");

        bytes32 expectedId = keccak256(abi.encode("vault", address(vault)));
        assertEq(ids.length, 1, "Unexpected number of ids returned");
        assertEq(ids[0], expectedId, "Incorrect id returned");
    }

    function testFactoryCreateAdapter() public {
        VaultMock newParentVault = new VaultMock(address(asset), owner);
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

        vm.prank(caller);
        vm.expectRevert(ERC4626Adapter.NotAuthorized.selector);
        adapter.setSkimRecipient(newRecipient);

        vm.prank(owner);
        vm.expectEmit();
        emit ERC4626Adapter.SetSkimRecipient(newRecipient);
        adapter.setSkimRecipient(newRecipient);

        assertEq(adapter.skimRecipient(), newRecipient, "Skim recipient not set correctly");
    }

    function testSkim(uint256 amount) public {
        amount = _boundAmount(amount);

        ERC20Mock token = new ERC20Mock();

        vm.prank(owner);
        adapter.setSkimRecipient(recipient);

        deal(address(token), address(adapter), amount);
        assertEq(token.balanceOf(address(adapter)), amount, "Adapter did not receive tokens");

        vm.expectEmit();
        emit ERC4626Adapter.Skim(address(token), amount);
        vm.prank(recipient);
        adapter.skim(address(token));

        assertEq(token.balanceOf(address(adapter)), 0, "Tokens not skimmed from adapter");
        assertEq(token.balanceOf(recipient), amount, "Recipient did not receive tokens");

        vm.expectRevert(ERC4626Adapter.NotAuthorized.selector);
        adapter.skim(address(token));
    }

    function testLossRealizationInitiallyZero() public {
        uint256 initialLoss = adapter.realisableLoss();
        assertEq(initialLoss, 0, "Initial realizable loss should be zero");
    }

    function testRealiseLossNotAuthorizedReverts() public {
        vm.expectRevert(ERC4626Adapter.NotAuthorized.selector);
        adapter.realiseLoss(hex"");
    }

    function testLossRealization(uint256 initialAmount, uint256 lossAmount) public {
        initialAmount = _boundAmount(initialAmount);
        lossAmount = bound(lossAmount, 0, initialAmount);

        // Setup.
        deal(address(asset), address(adapter), initialAmount);
        vm.prank(address(parentVault));
        adapter.allocateIn(hex"", initialAmount);

        // Loss detection.
        vm.mockCall(
            address(vault),
            abi.encodeWithSelector(IERC4626.previewWithdraw.selector, initialAmount),
            abi.encode(initialAmount - lossAmount)
        );
        uint256 snapshot = vm.snapshot();
        vm.prank(address(parentVault));
        adapter.allocateIn(hex"", 0);
        assertEq(adapter.realisableLoss(), lossAmount, "Loss should have been tracked");
        vm.revertTo(snapshot);
        vm.prank(address(parentVault));
        adapter.allocateOut(hex"", 0);
        assertEq(adapter.realisableLoss(), lossAmount, "Loss should have been tracked");

        // Realisation.
        vm.prank(address(parentVault));
        uint256 realizedLoss = adapter.realiseLoss(hex"");
        assertEq(realizedLoss, lossAmount, "Realized loss should match expected loss");
        assertEq(adapter.realisableLoss(), 0, "Realizable loss should be reset to zero");

        // Can't realise loss twice.
        vm.prank(address(parentVault));
        uint256 secondRealizedLoss = adapter.realiseLoss(hex"");
        assertEq(secondRealizedLoss, 0, "Second realized loss should be zero");
    }

    function testCumulativeLossRealization(
        uint256 initialAmount,
        uint256 firstLoss,
        uint256 secondLoss,
        uint256 depositAmount,
        uint256 withdrawAmount
    ) public {
        initialAmount = _boundAmount(initialAmount);
        firstLoss = bound(firstLoss, 0, initialAmount);
        secondLoss = bound(secondLoss, 0, initialAmount - firstLoss);
        depositAmount = _boundAmount(depositAmount);
        withdrawAmount = bound(withdrawAmount, 0, depositAmount + initialAmount);

        deal(address(asset), address(adapter), initialAmount + depositAmount);
        vm.prank(address(parentVault));
        adapter.allocateIn(hex"", initialAmount);

        // First loss
        vm.mockCall(
            address(vault),
            abi.encodeWithSelector(IERC4626.previewWithdraw.selector, initialAmount),
            abi.encode(initialAmount - firstLoss)
        );
        vm.prank(address(parentVault));
        adapter.allocateIn(hex"", 0);
        assertEq(adapter.realisableLoss(), firstLoss, "First loss should be tracked");

        // Second loss
        vm.mockCall(
            address(vault),
            abi.encodeWithSelector(IERC4626.previewWithdraw.selector, initialAmount),
            abi.encode(initialAmount - firstLoss - secondLoss)
        );
        vm.prank(address(parentVault));
        adapter.allocateIn(hex"", 0);
        assertEq(adapter.realisableLoss(), firstLoss + secondLoss, "Cumulative loss should be tracked");

        // Depositing doesn't change the loss.
        vm.prank(address(parentVault));
        adapter.allocateIn(hex"", depositAmount);
        assertEq(adapter.realisableLoss(), firstLoss + secondLoss, "Loss should not change");

        // Withdrawing doesn't change the loss.
        vm.prank(address(parentVault));
        adapter.allocateOut(hex"", withdrawAmount);
        assertEq(adapter.realisableLoss(), firstLoss + secondLoss, "Loss should not change");

        // Realise loss
        vm.prank(address(parentVault));
        uint256 realizedLoss = adapter.realiseLoss(hex"");
        assertEq(realizedLoss, firstLoss + secondLoss, "Should realize the full cumulative loss");
        assertEq(adapter.realisableLoss(), 0, "Realizable loss should be reset to zero");
    }
}
