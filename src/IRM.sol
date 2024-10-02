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
    // It is manipulable as is, hence the require.
    // Alternatively, this could be computed offchain in the custodial solution.
    // Note also that the formula and its coefficients are arbitrary at the moment:
    // it only illustrates that the rate is meant to be controlling totalAssets to target realAssets.
    function setRate() public {
        require(msg.sender == rateManager);
        rate = vault.realRate() + vault.realAssets() / 30 days - vault.totalAssets() / 30 days;
    }
}
