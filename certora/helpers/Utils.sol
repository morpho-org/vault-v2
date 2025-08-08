// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Morpho Association
pragma solidity 0.8.28;

import "../../src/libraries/ConstantsLib.sol";
import {MarketParams, Id, MarketParamsLib} from "../../lib/morpho-blue/src/libraries/MarketParamsLib.sol";

interface IReturnFactory {
    function factory() external view returns (address);
}

contract Utils {
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

    function marketParamsToBytes(MarketParams memory marketParams) external pure returns (bytes memory) {
        return abi.encode(marketParams);
    }

    function id(MarketParams memory marketParams) external pure returns (Id) {
        return MarketParamsLib.id(marketParams);
    }

    function havocAll() external {
        this.havocAll();
    }
}
