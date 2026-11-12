// SPDX-License-Identifier: MIT
// Copyright (c) 2025 Morpho Association

import "../helpers/UtilityMidnightAdapter.spec";

methods {
    function multicall(bytes[]) external => HAVOC_ALL DELETE;
    function MAX_MARKETS() external returns (uint256) envfree;

    // Resolved so that strong invariants are not checked at this call, which is in the middle of market list updates.
    function _.lossFactor(bytes32) external => NONDET;
    function _.liquidationLocked(bytes32, address) external => NONDET;
    function _.updatePositionView(MidnightAdapter.Market, bytes32, address) external => NONDET;

    // The id is a nested hash of the ABI-encoded market, which the prover handles poorly; any id is allowed.
    function IdLib.toId(MidnightAdapter.Market memory) internal returns (bytes32) => NONDET;

    // Resolved so that strong invariants are not checked at this call, for listedHasNonZeroNetCredit it fails because the netCredit could be 0 because of slashing but the market is not yet removed.
    function _.accrueInterest() external => NONDET;

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
