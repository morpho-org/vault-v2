// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.28;

import {IIRM} from "./interfaces/IIRM.sol";
import {IVaultV2} from "./interfaces/IVaultV2.sol";

contract IRM is IIRM {
    // Note that owner may be controlled by the curator, if the curator has the ability to change the IRM.
    address public immutable owner;

    // rate per second, in WAD
    uint256 internal _rate;

    constructor(address _owner) {
        owner = _owner;
    }

    function setRate(uint256 newRate) public {
        require(msg.sender == owner);
        _rate = newRate;
    }

    function rate(uint256, uint256) external view returns (uint256) {
        return _rate;
    }
}
