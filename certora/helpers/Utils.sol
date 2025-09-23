// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Morpho Association
pragma solidity 0.8.28;

import "../../src/libraries/ConstantsLib.sol";
import {IMorpho, MarketParams, Id} from "../../lib/morpho-blue/src/interfaces/IMorpho.sol";
import {MarketParamsLib} from "../../lib/morpho-blue/src/libraries/MarketParamsLib.sol";
import {MorphoBalancesLib} from "../../lib/morpho-blue/src/libraries/periphery/MorphoBalancesLib.sol";
import {MorphoLib} from "../../lib/morpho-blue/src/libraries/periphery/MorphoLib.sol";
import {SharesMathLib} from "../../lib/morpho-blue/src/libraries/SharesMathLib.sol";

interface IReturnFactory {
    function factory() external view returns (address);
}

contract Utils {
    using MarketParamsLib for MarketParams;
    using SharesMathLib for uint256;

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

    function expectedSupplyAssets(IMorpho morpho, MarketParams memory marketParams, address user)
        external
        view
        returns (uint256)
    {
        Id marketId = marketParams.id();
        uint256 supplyShares = morpho.position(marketId, user).supplyShares;
        (uint256 totalSupplyAssets, uint256 totalSupplyShares,,) =
            MorphoBalancesLib.expectedMarketBalances(morpho, marketParams);

        return supplyShares.toAssetsDown(totalSupplyAssets, totalSupplyShares);
    }

    function decodeMarketParams(bytes memory data) external pure returns (MarketParams memory) {
        return abi.decode(data, (MarketParams));
    }

    function id(MarketParams memory marketParams) external pure returns (Id) {
        return MarketParamsLib.id(marketParams);
    }

    function havocAll() external {
        this.havocAll();
    }
}
