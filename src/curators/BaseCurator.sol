// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.27;

import {ICurator} from "../interfaces/ICurator.sol";
import {VaultsV2} from "../VaultsV2.sol";

abstract contract BaseCurator is ICurator {
    function authorizeMulticall(address sender, bytes[] calldata bundle) external view virtual;
}
