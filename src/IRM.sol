// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.28;

import {IIRM} from "./interfaces/IIRM.sol";
import {IVaultV2} from "./interfaces/IVaultV2.sol";

contract IRM is IIRM {
    // Note that owner may be controlled by the curator, if the curator has the ability to change the IRM.
    address public immutable owner;
    IVaultV2 public immutable vault;

    // Notice how this makes it O(1) in the number of markets.
    int256 public interestPerSecond;

    constructor(address _owner, IVaultV2 _vault) {
        owner = _owner;
        vault = _vault;
    }

    // This is most likely O(n) in the number of markets.
    // It is manipulable as is, hence the require.
    // Alternatively, this could be computed offchain in the custodial solution.
    // Note also that the formula and its coefficients are arbitrary at the moment:
    // it only illustrates that interestPerSecond is meant to be controlling totalAssets to target realAssets.
    function setInterest() public {
        require(msg.sender == owner);
        int256 excessAssets = int256(vault.realAssets()) - int256(vault.totalAssets());
        interestPerSecond = excessAssets / 30 days;
    }
}
