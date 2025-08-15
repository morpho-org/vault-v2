// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Morpho Association
pragma solidity 0.8.28;

import "../../src/libraries/ConstantsLib.sol";
import {IMorphoMarketV1Adapter} from "../../src/adapters/interfaces/IMorphoMarketV1Adapter.sol";
import {MarketParams, Id} from "../../lib/morpho-blue/src/interfaces/IMorpho.sol";
import {MarketParamsLib} from "../../lib/morpho-blue/src/libraries/MarketParamsLib.sol";

interface IReturnFactory {
    function factory() external view returns (address);
}

contract Utils {
    using MarketParamsLib for MarketParams;

    function toBytes4(bytes memory data) public pure returns (bytes4) {
        return bytes4(data);
    }

    function wad() external pure returns (uint256) {
        return WAD;
    }

    function timelockCap() external pure returns (uint256) {
        return TIMELOCK_CAP;
    }

    function maxPerformanceFee() external pure returns (uint256) {
        return MAX_PERFORMANCE_FEE;
    }

    function maxManagementFee() external pure returns (uint256) {
        return MAX_MANAGEMENT_FEE;
    }

    function maxForceDeallocatePenalty() external pure returns (uint256) {
        return MAX_FORCE_DEALLOCATE_PENALTY;
    }

    function factory(address adapter) external view returns (address) {
        return IReturnFactory(adapter).factory();
    }

    function isAllocated(address adapter, MarketParams memory mp1) external view returns (bool) {
        address loanToken;
        address collateralToken;
        address oracle;
        address irm;
        uint256 lltv;

        MarketParams memory mp2;
        for (uint256 i = 0; i < IMorphoMarketV1Adapter(adapter).marketParamsListLength(); i++) {
            (loanToken, collateralToken, oracle, irm, lltv) = IMorphoMarketV1Adapter(adapter).marketParamsList(i);
            mp2.loanToken = loanToken;
            mp2.collateralToken = collateralToken;
            mp2.oracle = oracle;
            mp2.irm = irm;
            mp2.lltv = lltv;

            if (Id.unwrap(mp1.id()) == Id.unwrap(mp2.id())) {
                return true;
            }
        }

        return false;
    }
}
