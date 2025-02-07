// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.27;

import {BaseCurator} from "./BaseCurator.sol";

// This curator completely opens up the reallocations to the public.
// It still restricts functions that could rug other users.
// Note that a more sensible curator would check that the reallocation amount to idle matches the amount to withdraw.

// Other restrictions the curator can put in place:
// - it could allow whitelisted users to manage the vault;
// - pause the withdrawals when the bank run is too likely (realAssets << totalAssets), by ensuring idle is empty;
// - pause the reallocationFromIdle, which is especially useful for the emergency curator, to allow maximum liquidity.
contract OpenCurator is BaseCurator {
    address public immutable owner;

    constructor(address _owner) {
        owner = _owner;
    }

    function authorizeMulticall(address sender, bytes[] calldata bundle) external view override {}
}
