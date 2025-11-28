// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Morpho Association
pragma solidity >=0.5.0;

import {MarketParams} from "../../../lib/morpho-blue/src/interfaces/IMorpho.sol";

interface IMovedSharesRecipient {
    function init(MarketParams memory marketParams, uint256 receivedShares, uint256 receivedAssets) external;
}
