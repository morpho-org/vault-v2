// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.27;

import {BaseAllocator} from "./BaseAllocator.sol";

// This allocator completely opens up the reallocations to the public.
// Note that a more sensible allocator would check that the reallocation amount to idle matches the amount to withdraw.

// Other restrictions the allocator can put in place:
// - it could allow whitelisted users to manage allocation of the vault;
// - pause the withdrawals when the bank run is too likely (realAssets << totalAssets), by ensuring idle is empty;
// - pause the reallocationFromIdle, which is especially useful for the emergency allocator, to allow maximum liquidity.
contract OpenAllocator is BaseAllocator {
    function authorizeMulticall(address sender, bytes[] calldata bundle) external view override {}
}
