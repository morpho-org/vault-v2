// SPDX-License-Identifier: MIT
// Copyright (c) 2025 Morpho Association
pragma solidity 0.8.37;

import {CollateralParams, Market} from "../../lib/midnight/src/interfaces/IMidnight.sol";
import {MidnightAdapter} from "../../src/adapters/MidnightAdapter.sol";

// This harness builds a one-collateral market in memory to avoid the prover's dirty bits in nested calldata.
contract MidnightAdapterHarness is MidnightAdapter {
    constructor(address _parentVault, address _midnight, uint256[] memory _durations)
        MidnightAdapter(_parentVault, _midnight, _durations)
    {}

    function withdrawToVaultOneCollateral(
        uint256 chainId,
        address marketMidnight,
        address loanToken,
        address collateralToken,
        uint256 lltv,
        uint256 liquidationCursor,
        address oracle,
        uint256 maturity,
        uint256 rcfThreshold,
        address enterGate,
        address liquidatorGate,
        uint256 withdrawnAssets
    ) external {
        Market memory market = Market({
            chainId: chainId,
            midnight: marketMidnight,
            loanToken: loanToken,
            collateralParams: new CollateralParams[](1),
            maturity: maturity,
            rcfThreshold: rcfThreshold,
            enterGate: enterGate,
            liquidatorGate: liquidatorGate
        });

        market.collateralParams[0] = CollateralParams({
            token: collateralToken, lltv: lltv, liquidationCursor: liquidationCursor, oracle: oracle
        });

        withdrawToVault(market, withdrawnAssets);
    }
}
