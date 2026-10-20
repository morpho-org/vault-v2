// SPDX-License-Identifier: MIT
// Copyright (c) 2025 Morpho Association

// Model of the adapter's environment: the parent vault is linked, Midnight, the asset and the vault's other adapters and gates are not in the scene.
// Assumes that external calls do not reenter the adapter: properties are checked on the body of each function, and Midnight's callbacks (onBuy, onSell) and the vault's calls into the adapter are checked as entry points of their own.
methods {
    function MAX_MARKETS() external returns (uint256) envfree;
    function multicall(bytes[]) external => HAVOC_ALL DELETE;

    // Resolved so that strong invariants are not checked at this call, which is in the middle of market list updates.
    function _.lossFactor(bytes32) external => NONDET;

    // The id is a nested hash of the ABI-encoded market, which the prover handles poorly; any id is allowed.
    function IdLib.toId(MidnightAdapter.Market memory) internal returns (bytes32) => NONDET;

    // Calls into Midnight, resolved so that they don't havoc the adapter's state. Midnight's take doesn't call back the adapter.
    function _.take(MidnightAdapter.Offer, bytes, uint256, address, address, address, bytes) external => NONDET;
    function _.withdraw(MidnightAdapter.Market, uint256, address, address) external => NONDET;
    function _.setConsumed(bytes32, uint128, address) external => NONDET;

    // The vault's calls into its adapters, which don't reenter this adapter.
    function _.allocate(bytes, uint256, bytes4, address) external => NONDET;
    function _.deallocate(bytes, uint256, bytes4, address) external => NONDET;

    // Views called by the vault's accrueInterest, resolved so that strong invariants are not checked at these calls (onBuy calls accrueInterest after Midnight credits the adapter, before the adapter records it).
    function _.realAssets() external => NONDET;
    function _.canReceiveShares(address) external => NONDET;
    function _.balanceOf(address) external => NONDET;

    // The asset is assumed to be a standard ERC20 token.
    function SafeERC20Lib.safeTransfer(address, address, uint256) internal => NONDET;
    function SafeERC20Lib.safeTransferFrom(address, address, address, uint256) internal => NONDET;
    function SafeERC20Lib.forceApproveMax(address, address) internal => NONDET;
}

// Prove that the market list has at most MAX_MARKETS entries.
strong invariant marketIdsLengthBounded()
    currentContract.marketIds.length <= MAX_MARKETS();

// Prove that the index stored for each listed market is its position in the list.
strong invariant marketIdsIndex()
    forall uint256 i. i < currentContract.marketIds.length => currentContract.marketData[currentContract.marketIds[i]].index == i
    {
        preserved {
            requireInvariant marketIdsLengthBounded();
            requireInvariant listedHasNonZeroNetCredit();
        }
    }

// Prove that a market in the list has a non-zero stored net credit.
strong invariant listedHasNonZeroNetCredit()
    forall uint256 i. i < currentContract.marketIds.length => currentContract.marketData[currentContract.marketIds[i]].netCredit != 0
    {
        preserved {
            requireInvariant marketIdsIndex();
        }
    }
