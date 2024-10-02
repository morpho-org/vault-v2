// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.27;

import {VaultsV2} from "./VaultsV2.sol";

contract IRM {
    // Could be made the same as the curator in VaultsV2.
    address public immutable rateManager;
    VaultsV2 public immutable vault;

    // Notice how this makes it O(1) in the number of markets.
    uint256 public rate;

    constructor(VaultsV2 _vault) {
        rateManager = msg.sender;
        vault = _vault;
    }

    // This is most likely O(n) in the number of markets.
    // Probably manipulable as is, hence the require.
    // Alternatively, this could be computed offchain in the custodial solution.
    function setRate() public {
        require(msg.sender == rateManager);
        rate = vault.realRate() + (vault.realAssets() - vault.totalAssets()) / 30 days;
    }
}
