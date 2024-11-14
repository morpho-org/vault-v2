// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.27;

import {ICurator} from "../interfaces/ICurator.sol";
import {VaultsV2} from "../VaultsV2.sol";

// This curator completely opens up the reallocations to the public.
// It still restricts functions that could rug other users.
// Note that a more sensible curator would check that the reallocation amount to idle matches the amount to withdraw.

// Other restrictions the curator can put in place:
// - it could allow whitelisted users to manage the vault;
// - pause the withdrawals when the bank run is too likely (realAssets << totalAssets), by ensuring idle is empty;
// - pause the reallocationFromIdle, which is especially useful for the emergency curator, to allow maximum liquidity.
contract OpenCurator is ICurator {
    address public immutable owner;

    constructor() {
        owner = msg.sender;
    }

    function authorizedMulticall(address sender, bytes[] calldata bundle) external view returns (bool) {
        if (sender == owner) return true;
        for (uint256 i = 0; i < bundle.length; i++) {
            if (restrictedFunction(bytes4(bundle[i]))) return false;
        }
        return true;
    }

    function restrictedFunction(bytes4 selector) internal pure returns (bool) {
        return selector == VaultsV2.setIRM.selector || selector == VaultsV2.enableNewMarket.selector;
    }
}
