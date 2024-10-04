// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.27;

import {VaultsV2} from "./VaultsV2.sol";

contract IRM {
    // Note that owner may be controlled by the curator, if the curator has the ability to change the IRM.
    address public immutable owner;
    VaultsV2 public immutable vault;

    // Notice how this makes it O(1) in the number of markets.
    uint256 public rate;

    constructor(address _owner, VaultsV2 _vault) {
        owner = _owner;
        vault = _vault;
    }

    // This is most likely O(n) in the number of markets.
    // It is manipulable as is, hence the require.
    // Alternatively, this could be computed offchain in the custodial solution.
    // Note also that the formula and its coefficients are arbitrary at the moment:
    // it only illustrates that the rate is meant to be controlling totalAssets to target realAssets.
    function setRate() public {
        require(msg.sender == owner);
        rate = vault.realRate() + vault.realAssets() / 30 days - vault.totalAssets() / 30 days;
    }
}
