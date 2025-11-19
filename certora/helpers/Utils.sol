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

    function maxMaxRate() external pure returns (uint256) {
        return MAX_MAX_RATE;
    }

    function expectedSupplyAssets(IMorpho morpho, MarketParams memory marketParams, uint256 supplyShares)
        external
        view
        returns (uint256)
    {
        Id marketId = marketParams.id();
        (uint256 totalSupplyAssets, uint256 totalSupplyShares,,) =
            MorphoBalancesLib.expectedMarketBalances(morpho, marketParams);

        return supplyShares.toAssetsDown(totalSupplyAssets, totalSupplyShares);
    }

    function id(MarketParams memory marketParams) external pure returns (Id) {
        return MarketParamsLib.id(marketParams);
    }

    function adapterId(address adapter) external pure returns (bytes32) {
        return keccak256(abi.encode("this", adapter));
    }

    function marketV1Id(address morpho) external pure returns (bytes32) {
        return keccak256(abi.encode("morphoMarketV1", morpho));
    }

    function collateralTokenId(address collateralToken) external pure returns (bytes32) {
        return keccak256(abi.encode("collateralToken", collateralToken));
    }

    function havocAll() external {
        this.havocAll();
    }
}
