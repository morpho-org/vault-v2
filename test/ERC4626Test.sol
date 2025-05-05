// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import "./BaseTest.sol";

// copied from solady.
contract ERC4626Test is BaseTest {
    // function testSingleDepositWithdraw(uint128 amount) public {
    //     if (amount == 0) amount = 1;

    //     uint256 aliceUnderlyingAmount = amount;

    //     address alice = address(0xABCD);

    //     deal(address(underlyingToken), alice, aliceUnderlyingAmount);

    //     vm.prank(alice);
    //     underlyingToken.approve(address(vault), aliceUnderlyingAmount);
    //     assertEq(underlyingToken.allowance(alice, address(vault)), aliceUnderlyingAmount);

    //     uint256 alicePreDepositBal = underlyingToken.balanceOf(alice);

    //     vm.prank(alice);
    //     uint256 aliceShareAmount = vault.deposit(aliceUnderlyingAmount, alice);

    //     // Expect exchange rate to be 1:1 on initial deposit.
    //     unchecked {
    //         assertEq(aliceUnderlyingAmount, aliceShareAmount);
    //         assertEq(vault.previewWithdraw(aliceShareAmount), aliceUnderlyingAmount);
    //         assertEq(vault.previewDeposit(aliceUnderlyingAmount), aliceShareAmount);
    //         assertEq(vault.totalSupply(), aliceShareAmount);
    //         assertEq(vault.totalAssets(), aliceUnderlyingAmount);
    //         assertEq(vault.balanceOf(alice), aliceShareAmount);
    //         assertEq(underlyingToken.balanceOf(alice), alicePreDepositBal - aliceUnderlyingAmount);
    //     }

    //     vm.prank(alice);
    //     vault.withdraw(aliceUnderlyingAmount, alice, alice);

    //     assertEq(vault.totalAssets(), 0);
    //     assertEq(vault.balanceOf(alice), 0);
    //     assertEq(underlyingToken.balanceOf(alice), alicePreDepositBal);
    // }

    // function testSingleMintRedeem(uint128 amount) public {
    //     if (amount == 0) amount = 1;

    //     uint256 aliceShareAmount = amount;

    //     address alice = address(0xABCD);

    //     deal(address(underlyingToken), alice, aliceShareAmount);

    //     vm.prank(alice);
    //     underlyingToken.approve(address(vault), aliceShareAmount);
    //     assertEq(underlyingToken.allowance(alice, address(vault)), aliceShareAmount);

    //     uint256 alicePreDepositBal = underlyingToken.balanceOf(alice);

    //     vm.prank(alice);
    //     uint256 aliceUnderlyingAmount = vault.mint(aliceShareAmount, alice);

    //     // Expect exchange rate to be 1:1 on initial mint.
    //     unchecked {
    //         assertEq(aliceShareAmount, aliceUnderlyingAmount);
    //         assertEq(vault.previewWithdraw(aliceShareAmount), aliceUnderlyingAmount);
    //         assertEq(vault.previewDeposit(aliceUnderlyingAmount), aliceShareAmount);
    //         assertEq(vault.totalSupply(), aliceShareAmount);
    //         assertEq(vault.totalAssets(), aliceUnderlyingAmount);
    //         assertEq(vault.balanceOf(alice), aliceUnderlyingAmount);
    //         assertEq(underlyingToken.balanceOf(alice), alicePreDepositBal - aliceUnderlyingAmount);
    //     }

    //     vm.prank(alice);
    //     vault.redeem(aliceShareAmount, alice, alice);

    //     assertEq(vault.totalAssets(), 0);
    //     assertEq(vault.balanceOf(alice), 0);
    //     assertEq(underlyingToken.balanceOf(alice), alicePreDepositBal);
    // }

    // function testMultipleMintDepositRedeemWithdraw() public {
    //     _testMultipleMintDepositRedeemWithdraw(0);
    // }

    // struct _TestTemps {
    //     uint256 slippage;
    //     address alice;
    //     address bob;
    //     uint256 mutationUnderlyingAmount;
    //     uint256 aliceUnderlyingAmount;
    //     uint256 aliceShareAmount;
    //     uint256 bobShareAmount;
    //     uint256 bobUnderlyingAmount;
    //     uint256 preMutationShareBal;
    //     uint256 preMutationBal;
    // }

    // function _testMultipleMintDepositRedeemWithdraw(uint256 slippage) public {
    //     // Scenario:
    //     // A = Alice, B = Bob
    //     //  ________________________________________________________
    //     // | Vault shares | A share | A assets | B share | B assets |
    //     // |::::::::::::::::::::::::::::::::::::::::::::::::::::::::|
    //     // | 1. Alice mints 2000 shares (costs 2000 tokens)         |
    //     // |--------------|---------|----------|---------|----------|
    //     // |         2000 |    2000 |     2000 |       0 |        0 |
    //     // |--------------|---------|----------|---------|----------|
    //     // | 2. Bob deposits 4000 tokens (mints 4000 shares)        |
    //     // |--------------|---------|----------|---------|----------|
    //     // |         6000 |    2000 |     2000 |    4000 |     4000 |
    //     // |--------------|---------|----------|---------|----------|
    //     // | 3. Vault mutates by +3000 tokens...                    |
    //     // |    (simulated yield returned from strategy)...         |
    //     // |--------------|---------|----------|---------|----------|
    //     // |         6000 |    2000 |     3000 |    4000 |     6000 |
    //     // |--------------|---------|----------|---------|----------|
    //     // | 4. Alice deposits 2000 tokens (mints 1333 shares)      |
    //     // |--------------|---------|----------|---------|----------|
    //     // |         7333 |    3333 |     4999 |    4000 |     6000 |
    //     // |--------------|---------|----------|---------|----------|
    //     // | 5. Bob mints 2000 shares (costs 3001 assets)           |
    //     // |    NOTE: Bob's assets spent got rounded up             |
    //     // |    NOTE: Alice's vault assets got rounded up           |
    //     // |--------------|---------|----------|---------|----------|
    //     // |         9333 |    3333 |     5000 |    6000 |     9000 |
    //     // |--------------|---------|----------|---------|----------|
    //     // | 6. Vault mutates by +3000 tokens...                    |
    //     // |    (simulated yield returned from strategy)            |
    //     // |    NOTE: Vault holds 17001 tokens, but sum of          |
    //     // |          assetsOf() is 17000.                          |
    //     // |--------------|---------|----------|---------|----------|
    //     // |         9333 |    3333 |     6071 |    6000 |    10929 |
    //     // |--------------|---------|----------|---------|----------|
    //     // | 7. Alice redeem 1333 shares (2428 assets)              |
    //     // |--------------|---------|----------|---------|----------|
    //     // |         8000 |    2000 |     3643 |    6000 |    10929 |
    //     // |--------------|---------|----------|---------|----------|
    //     // | 8. Bob withdraws 2928 assets (1608 shares)             |
    //     // |--------------|---------|----------|---------|----------|
    //     // |         6392 |    2000 |     3643 |    4392 |     8000 |
    //     // |--------------|---------|----------|---------|----------|
    //     // | 9. Alice withdraws 3643 assets (2000 shares)           |
    //     // |    NOTE: Bob's assets have been rounded back up        |
    //     // |--------------|---------|----------|---------|----------|
    //     // |         4392 |       0 |        0 |    4392 |     8001 |
    //     // |--------------|---------|----------|---------|----------|
    //     // | 10. Bob redeem 4392 shares (8001 tokens)               |
    //     // |--------------|---------|----------|---------|----------|
    //     // |            0 |       0 |        0 |       0 |        0 |
    //     // |______________|_________|__________|_________|__________|

    //     _TestTemps memory t;
    //     t.slippage = slippage;
    //     t.alice = address(0x9988776655443322110000112233445566778899);
    //     t.bob = address(0x1122334455667788990000998877665544332211);

    //     t.mutationUnderlyingAmount = 3000;

    //     deal(address(underlyingToken), t.alice, 4000);

    //     vm.prank(t.alice);
    //     underlyingToken.approve(address(vault), 4000);

    //     assertEq(underlyingToken.allowance(t.alice, address(vault)), 4000);

    //     deal(address(underlyingToken), t.bob, 7001);

    //     vm.prank(t.bob);
    //     underlyingToken.approve(address(vault), 7001);

    //     assertEq(underlyingToken.allowance(t.bob, address(vault)), 7001);

    //     _testMultipleMintDepositRedeemWithdraw1(t);
    //     _testMultipleMintDepositRedeemWithdraw2(t);
    //     _testMultipleMintDepositRedeemWithdraw3(t);
    //     _testMultipleMintDepositRedeemWithdraw4(t);
    //     _testMultipleMintDepositRedeemWithdraw5(t);
    //     _testMultipleMintDepositRedeemWithdraw6(t);
    //     _testMultipleMintDepositRedeemWithdraw7(t);
    //     _testMultipleMintDepositRedeemWithdraw8(t);
    //     _testMultipleMintDepositRedeemWithdraw9(t);
    //     _testMultipleMintDepositRedeemWithdraw10(t);
    // }

    // function _testMultipleMintDepositRedeemWithdraw1(_TestTemps memory t) internal {
    //     // 1. Alice mints 2000 shares (costs 2000 tokens)
    //     vm.prank(t.alice);
    //     vm.expectEmit(true, true, true, true);
    //     emit EventsLib.Deposit(t.alice, t.alice, 2000, 2000);
    //     t.aliceUnderlyingAmount = vault.mint(2000, t.alice);

    //     t.aliceShareAmount = vault.previewDeposit(t.aliceUnderlyingAmount);

    //     // Expect to have received the requested mint amount.
    //     assertEq(t.aliceShareAmount, 2000);
    //     assertEq(vault.balanceOf(t.alice), t.aliceShareAmount);
    //     assertEq(vault.previewMint(t.aliceShareAmount), t.aliceUnderlyingAmount);
    //     assertEq(vault.previewDeposit(t.aliceUnderlyingAmount), t.aliceShareAmount);

    //     // Expect a 1:1 ratio before mutation.
    //     assertEq(t.aliceUnderlyingAmount, 2000);

    //     // Sanity check.
    //     assertEq(vault.totalSupply(), t.aliceShareAmount);
    //     assertEq(vault.totalAssets(), t.aliceUnderlyingAmount);
    // }

    // function _testMultipleMintDepositRedeemWithdraw2(_TestTemps memory t) internal {
    //     // 2. Bob deposits 4000 tokens (mints 4000 shares)
    //     unchecked {
    //         vm.prank(t.bob);
    //         vm.expectEmit(true, true, true, true);
    //         emit EventsLib.Deposit(t.bob, t.bob, 4000, 4000);
    //         t.bobShareAmount = vault.deposit(4000, t.bob);
    //         t.bobUnderlyingAmount = vault.previewWithdraw(t.bobShareAmount);

    //         // Expect to have received the requested underlying amount.
    //         assertEq(t.bobUnderlyingAmount, 4000);
    //         assertEq(vault.balanceOf(t.bob), t.bobShareAmount);
    //         assertEq(vault.previewMint(t.bobShareAmount), t.bobUnderlyingAmount);
    //         assertEq(vault.previewDeposit(t.bobUnderlyingAmount), t.bobShareAmount);

    //         // Expect a 1:1 ratio before mutation.
    //         assertEq(t.bobShareAmount, t.bobUnderlyingAmount);

    //         // Sanity check.
    //         t.preMutationShareBal = t.aliceShareAmount + t.bobShareAmount;
    //         t.preMutationBal = t.aliceUnderlyingAmount + t.bobUnderlyingAmount;
    //         assertEq(vault.totalSupply(), t.preMutationShareBal);
    //         assertEq(vault.totalAssets(), t.preMutationBal);
    //         assertEq(vault.totalSupply(), 6000);
    //         assertEq(vault.totalAssets(), 6000);
    //     }
    // }

    // function _testMultipleMintDepositRedeemWithdraw3(_TestTemps memory t) internal {
    //     // 3. Vault mutates by +3000 tokens...                    |
    //     //    (simulated yield returned from strategy)...
    //     // The Vault now contains more tokens than deposited which causes the exchange rate to change.
    //     // Alice share is 33.33% of the Vault, Bob 66.66% of the Vault.
    //     // Alice's share count stays the same but the underlying amount changes from 2000 to 3000.
    //     // Bob's share count stays the same but the underlying amount changes from 4000 to 6000.
    //     unchecked {
    //         deal(address(underlyingToken), address(vault), t.mutationUnderlyingAmount);
    //         assertEq(vault.totalSupply(), t.preMutationShareBal);
    //         assertEq(vault.totalAssets(), t.preMutationBal + t.mutationUnderlyingAmount);
    //         assertEq(vault.balanceOf(t.alice), t.aliceShareAmount);
    //         assertEq(
    //             vault.previewMint(t.aliceShareAmount),
    //             t.aliceUnderlyingAmount + (t.mutationUnderlyingAmount / 3) * 1 - t.slippage
    //         );
    //         assertEq(vault.balanceOf(t.bob), t.bobShareAmount);
    //         assertEq(
    //             vault.previewMint(t.bobShareAmount),
    //             t.bobUnderlyingAmount + (t.mutationUnderlyingAmount / 3) * 2 - t.slippage
    //         );
    //     }
    // }

    // function _testMultipleMintDepositRedeemWithdraw4(_TestTemps memory t) internal {
    //     // 4. Alice deposits 2000 tokens (mints 1333 shares)
    //     vm.prank(t.alice);
    //     vault.deposit(2000, t.alice);

    //     assertEq(vault.totalSupply(), 7333);
    //     assertEq(vault.balanceOf(t.alice), 3333);
    //     assertEq(vault.previewMint(3333), 4999);
    //     assertEq(vault.balanceOf(t.bob), 4000);
    //     assertEq(vault.previewMint(4000), 6000);
    // }

    // function _testMultipleMintDepositRedeemWithdraw5(_TestTemps memory t) internal {
    //     // 5. Bob mints 2000 shares (costs 3001 assets)
    //     // NOTE: Bob's assets spent got rounded up
    //     // NOTE: Alices's vault assets got rounded up
    //     unchecked {
    //         vm.prank(t.bob);
    //         vault.mint(2000, t.bob);

    //         assertEq(vault.totalSupply(), 9333);
    //         assertEq(vault.balanceOf(t.alice), 3333);
    //         assertEq(vault.previewMint(3333), 5000 - t.slippage);
    //         assertEq(vault.balanceOf(t.bob), 6000);
    //         assertEq(vault.previewMint(6000), 9000);

    //         // Sanity checks:
    //         // Alice and t.bob should have spent all their tokens now
    //         assertEq(underlyingToken.balanceOf(t.alice), 0);
    //         assertEq(underlyingToken.balanceOf(t.bob) - t.slippage, 0);
    //         // Assets in vault: 4k (t.alice) + 7k (t.bob) + 3k (yield) + 1 (round up)
    //         assertEq(vault.totalAssets(), 14001 - t.slippage);
    //     }
    // }

    // function _testMultipleMintDepositRedeemWithdraw6(_TestTemps memory t) internal {
    //     // 6. Vault mutates by +3000 tokens
    //     // NOTE: Vault holds 17001 tokens, but sum of assetsOf() is 17000.
    //     unchecked {
    //         deal(address(underlyingToken), address(vault), t.mutationUnderlyingAmount);
    //         assertEq(vault.previewMint(vault.balanceOf(t.alice)), 6071 - t.slippage);
    //         assertEq(vault.previewMint(vault.balanceOf(t.bob)), 10929 - t.slippage);
    //         assertEq(vault.totalSupply(), 9333);
    //         assertEq(vault.totalAssets(), 17001 - t.slippage);
    //     }
    // }

    // function _testMultipleMintDepositRedeemWithdraw7(_TestTemps memory t) internal {
    //     // 7. Alice redeem 1333 shares (2428 assets)
    //     unchecked {
    //         vm.prank(t.alice);
    //         vault.redeem(1333, t.alice, t.alice);

    //         assertEq(underlyingToken.balanceOf(t.alice), 2428 - t.slippage);
    //         assertEq(vault.totalSupply(), 8000);
    //         assertEq(vault.totalAssets(), 14573);
    //         assertEq(vault.balanceOf(t.alice), 2000);
    //         assertEq(vault.previewMint(2000), 3643);
    //         assertEq(vault.balanceOf(t.bob), 6000);
    //         assertEq(vault.previewMint(6000), 10929);
    //     }
    // }

    // function _testMultipleMintDepositRedeemWithdraw8(_TestTemps memory t) internal {
    //     // 8. Bob withdraws 2929 assets (1608 shares)
    //     unchecked {
    //         vm.prank(t.bob);
    //         vault.withdraw(2929, t.bob, t.bob);

    //         assertEq(underlyingToken.balanceOf(t.bob) - t.slippage, 2929);
    //         assertEq(vault.totalSupply(), 6392);
    //         assertEq(vault.totalAssets(), 11644);
    //         assertEq(vault.balanceOf(t.alice), 2000);
    //         assertEq(vault.previewMint(2000), 3643);
    //         assertEq(vault.balanceOf(t.bob), 4392);
    //         assertEq(vault.previewMint(4392), 8000);
    //     }
    // }

    // function _testMultipleMintDepositRedeemWithdraw9(_TestTemps memory t) internal {
    //     // 9. Alice withdraws 3643 assets (2000 shares)
    //     // NOTE: Bob's assets have been rounded back up
    //     unchecked {
    //         vm.prank(t.alice);
    //         vm.expectEmit(true, true, true, true);
    //         emit EventsLib.Withdraw(t.alice, t.alice, t.alice, 3643, 2000);
    //         vault.withdraw(3643, t.alice, t.alice);
    //         assertEq(underlyingToken.balanceOf(t.alice), 6071 - t.slippage);
    //         assertEq(vault.totalSupply(), 4392);
    //         assertEq(vault.totalAssets(), 8001);
    //         assertEq(vault.balanceOf(t.alice), 0);
    //         assertEq(vault.previewMint(0), 0);
    //         assertEq(vault.balanceOf(t.bob), 4392);
    //         assertEq(vault.previewMint(4392), 8001 - t.slippage);
    //     }
    // }

    // function _testMultipleMintDepositRedeemWithdraw10(_TestTemps memory t) internal {
    //     // 10. Bob redeem 4392 shares (8001 tokens)
    //     unchecked {
    //         vm.prank(t.bob);
    //         vm.expectEmit(true, true, true, true);
    //         emit EventsLib.Withdraw(t.bob, t.bob, t.bob, 8001 - t.slippage, 4392);
    //         vault.redeem(4392, t.bob, t.bob);
    //         assertEq(underlyingToken.balanceOf(t.bob), 10930);
    //         assertEq(vault.totalSupply(), 0);
    //         assertEq(vault.totalAssets() - t.slippage, 0);
    //         assertEq(vault.balanceOf(t.alice), 0);
    //         assertEq(vault.previewMint(0), 0);
    //         assertEq(vault.balanceOf(t.bob), 0);
    //         assertEq(vault.previewMint(0), 0);

    //         // Sanity check
    //         assertEq(underlyingToken.balanceOf(address(vault)) - t.slippage, 0);
    //     }
    // }

    // function testDepositWithNotEnoughApprovalReverts() public {
    //     deal(address(underlyingToken), address(this), 0.5e18);
    //     underlyingToken.approve(address(vault), 0.5e18);
    //     assertEq(underlyingToken.allowance(address(this), address(vault)), 0.5e18);

    //     vm.expectRevert(ErrorsLib.TransferFromReverted.selector);
    //     vault.deposit(1e18, address(this));
    // }

    // function testWithdrawWithNotEnoughUnderlyingAmountReverts() public {
    //     deal(address(underlyingToken), address(this), 0.5e18);
    //     underlyingToken.approve(address(vault), 0.5e18);

    //     vault.deposit(0.5e18, address(this));

    //     vm.expectRevert(stdError.arithmeticError);
    //     vault.withdraw(1e18, address(this), address(this));
    // }

    // function testRedeemWithNotEnoughShareAmountReverts() public {
    //     deal(address(underlyingToken), address(this), 0.5e18);
    //     underlyingToken.approve(address(vault), 0.5e18);

    //     vault.deposit(0.5e18, address(this));

    //     vm.expectRevert(stdError.arithmeticError);
    //     vault.redeem(1e18, address(this), address(this));
    // }

    // function testWithdrawWithNoUnderlyingAmountReverts() public {
    //     vm.expectRevert(stdError.arithmeticError);
    //     vault.withdraw(1e18, address(this), address(this));
    // }

    // function testRedeemWithNoShareAmountReverts() public {
    //     vm.expectRevert(stdError.arithmeticError);
    //     vault.redeem(1e18, address(this), address(this));
    // }

    // function testDepositWithNoApprovalReverts() public {
    //     vm.expectRevert(ErrorsLib.TransferFromReverted.selector);
    //     vault.deposit(1e18, address(this));
    // }

    // function testMintWithNoApprovalReverts() public {
    //     vm.expectRevert(ErrorsLib.TransferFromReverted.selector);
    //     vault.mint(1e18, address(this));
    // }

    // function testMintZero() public {
    //     vault.mint(0, address(this));

    //     assertEq(vault.balanceOf(address(this)), 0);
    //     assertEq(vault.previewMint(0), 0);
    //     assertEq(vault.totalSupply(), 0);
    //     assertEq(vault.totalAssets(), 0);
    // }

    // function testWithdrawZero() public {
    //     vault.withdraw(0, address(this), address(this));

    //     assertEq(vault.balanceOf(address(this)), 0);
    //     assertEq(vault.previewWithdraw(0), 0);
    //     assertEq(vault.totalSupply(), 0);
    //     assertEq(vault.totalAssets(), 0);
    // }

    // function testVaultInteractionsForSomeoneElse() public {
    //     // init 2 users with a 1e18 balance
    //     address alice = address(0xABCD);
    //     address bob = address(0xDCBA);
    //     deal(address(underlyingToken), alice, 1e18);
    //     deal(address(underlyingToken), bob, 1e18);

    //     vm.prank(alice);
    //     underlyingToken.approve(address(vault), 1e18);

    //     vm.prank(bob);
    //     underlyingToken.approve(address(vault), 1e18);

    //     // alice deposits 1e18 for bob
    //     vm.prank(alice);
    //     vm.expectEmit(true, true, true, true);
    //     emit EventsLib.Deposit(alice, bob, 1e18, 1e18);
    //     vault.deposit(1e18, bob);

    //     assertEq(vault.balanceOf(alice), 0);
    //     assertEq(vault.balanceOf(bob), 1e18);
    //     assertEq(underlyingToken.balanceOf(alice), 0);

    //     // bob mint 1e18 for alice
    //     vm.prank(bob);
    //     vm.expectEmit(true, true, true, true);
    //     emit EventsLib.Deposit(bob, alice, 1e18, 1e18);
    //     vault.mint(1e18, alice);
    //     assertEq(vault.balanceOf(alice), 1e18);
    //     assertEq(vault.balanceOf(bob), 1e18);
    //     assertEq(underlyingToken.balanceOf(bob), 0);

    //     // alice redeem 1e18 for bob
    //     vm.prank(alice);
    //     vm.expectEmit(true, true, true, true);
    //     emit EventsLib.Withdraw(alice, bob, alice, 1e18, 1e18);
    //     vault.redeem(1e18, bob, alice);

    //     assertEq(vault.balanceOf(alice), 0);
    //     assertEq(vault.balanceOf(bob), 1e18);
    //     assertEq(underlyingToken.balanceOf(alice), 1e18);

    //     // bob withdraw 1e18 for alice
    //     vm.prank(bob);
    //     vm.expectEmit(true, true, true, true);
    //     emit EventsLib.Withdraw(bob, alice, bob, 1e18, 1e18);
    //     vault.withdraw(1e18, alice, bob);

    //     assertEq(vault.balanceOf(alice), 0);
    //     assertEq(vault.balanceOf(bob), 0);
    //     assertEq(underlyingToken.balanceOf(alice), 1e18);
    // }
}
