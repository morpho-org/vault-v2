// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Morpho Association
pragma solidity 0.8.28;

import "../../src/libraries/ConstantsLib.sol";
import {MarketParamsLib, MarketParams, MorphoBalancesLib, IMorpho} from "../../src/adapters/MorphoMarketV1Adapter.sol";

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

    // To remove when chainsec specs are merged.
    function decodeMarketParams(bytes memory data) external pure returns (MarketParams memory) {
        return abi.decode(data, (MarketParams));
    }

    function expectedSupplyAssets(address morpho, MarketParams memory marketParams, address user)
        external
        view
        returns (uint256)
    {
        return MorphoBalancesLib.expectedSupplyAssets(IMorpho(morpho), marketParams, user);
    }
}
