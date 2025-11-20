// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Morpho Association
pragma solidity 0.8.28;

import {MarketParams, Id} from "../../lib/morpho-blue/src/interfaces/IMorpho.sol";
import {MarketParamsLib} from "../../lib/morpho-blue/src/libraries/MarketParamsLib.sol";

contract MarketParamsStore {
    using MarketParamsLib for MarketParams;

    address internal immutable loanToken;
    address internal immutable collateralToken;
    address internal immutable oracle;
    address internal immutable irm;
    uint256 internal immutable lltv;
    Id internal immutable id;

    constructor(MarketParams memory _marketParams) {
        loanToken = _marketParams.loanToken;
        collateralToken = _marketParams.collateralToken;
        oracle = _marketParams.oracle;
        irm = _marketParams.irm;
        lltv = _marketParams.lltv;
        id = _marketParams.id();
    }

    function marketParamsAndId() public view returns (MarketParams memory, bytes32) {
        return (
            MarketParams({
                loanToken: loanToken, collateralToken: collateralToken, oracle: oracle, irm: irm, lltv: lltv
            }),
            Id.unwrap(id)
        );
    }
}
