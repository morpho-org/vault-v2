// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.27;

import {VaultsV2} from "../../src/VaultsV2.sol";
import {ICurator} from "../../src/interfaces/ICurator.sol";

contract VaultsV2Mock is VaultsV2 {
    constructor(address _curator, address _guardian, address _asset, string memory _name, string memory _symbol)
        VaultsV2(_curator, _guardian, _asset, _name, _symbol)
    {}

    function setCurator(address newCurator) external {
        curator = ICurator(newCurator);
    }
}
