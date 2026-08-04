// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Morpho Association

using BlueAdapterV3 as BlueAdapterV3;
using MorphoHarness as MorphoBlue;
using RevertCondition as RevertCondition;

methods {

    // Assume the IRM borrow rate is constant, since skim does not interact with borrowing
    // and accrueInterest should not depend on the skim operation.
    function _.borrowRateView(MorphoHarness.MarketParams, MorphoHarness.Market) external => CONSTANT;

    // safeTransfer summarised to track the adapter's token balances in a ghost mapping,
    // avoiding the need to model full ERC20 contracts.
    function SafeERC20Lib.safeTransfer(address token, address to, uint256 value) internal => summarySafeTransferFrom(token, executingContract, to, value);

    // balanceOf summarised to return the adapter's ghost-tracked balance when queried for the adapter,
    // and a non-deterministic value otherwise.
    function _.balanceOf(address account) external => summaryBalanceOf(calledContract, account) expect(uint256) ALL;
}

// Tracks the adapter's token balances across transfers.
ghost mapping(address => uint256) adapterBalanceOf;

// Returns the ghost-tracked balance for the adapter, and a non-deterministic value for all other accounts.
function summaryBalanceOf(address token, address account) returns uint256 {
    if (account == BlueAdapterV3) {
        return adapterBalanceOf[token];
    }

    // Return a non-deterministic value for non-adapter accounts
    uint256 balance;
    return balance;
}

// Models safeTransfer by updating the adapter's ghost balances on sends/receives.
function summarySafeTransferFrom(address token, address from, address to, uint256 amount) {
    if (from == BlueAdapterV3) {
        // Safe require: mirrors the ERC20 revert on insufficient balance.
        adapterBalanceOf[token] = require_uint256(adapterBalanceOf[token] - amount);
    }
    if (to == BlueAdapterV3) {
        // Safe require: mirrors the ERC20 revert on balance overflow.
        adapterBalanceOf[token] = require_uint256(adapterBalanceOf[token] + amount);
    }
}

// Verifies that calling skim does not change the adapter's accounting (realAssets) and
// skim only transfers tokens already held by the adapter to skimRecipient.
rule skimDoesNotAffectAccountingBlueAdapterV3(env e, address token) {
    uint256 realAssetsBefore = realAssets(e);

    skim(e, token);

    uint256 realAssetsAfter = realAssets(e);
    assert realAssetsAfter == realAssetsBefore;
}

// Verifies that setSkimRecipient reverts if and only if the timelock conditions are not met:
// 1. the call data was not submitted,
// 2. the timelock has not expired,
// 3. the function is abdicated.
// See timelockFailsBlueAdapterV3() in "../helpers/RevertCondition.sol"
// The helper contract is called first, so this specification can miss trivial revert conditions like e.msg.value != 0.
rule setSkimRecipientRevertConditionBlueAdapterV3(env e, address newRecipient) {
    bool revertCondition = RevertCondition.setSkimRecipient(e, newRecipient);

    setSkimRecipient@withrevert(e, newRecipient);

    assert revertCondition <=> lastReverted;
}
