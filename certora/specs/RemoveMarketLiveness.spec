// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Morpho Association

using MorphoMarketV1Adapter as MorphoMarketV1Adapter;
using Morpho as Morpho;
using Utils as Utils;

methods {
    function _.extSloads(bytes32[]) external returns (bytes32[]) => NONDET DELETE;
    function _.multicall(bytes[] calldata data) external => HAVOC_ALL DELETE;
    function _.supplyShares(address morpho, VaultV2.Id id, address user) external returns (uint256) => summarySupplyShares(morpho, id, user);

    function MorphoMarketV1Adapter.marketParamsListLength() external returns (uint256) envfree;
    function MorphoMarketV1Adapter.marketParamsList(uint256) external returns (address, address, address, address, uint256) envfree;
    function Utils.decodeMarketParams(bytes data) external returns (VaultV2.MarketParams memory) envfree;

    function _.deallocate(bytes, uint256, bytes4, address) external => DISPATCHER(true);
}

function summarySupplyShares(address morpho, VaultV2.Id id, address user) returns uint256 {
    return Morpho.position(morpho, id, user).supplyShares;
}

rule canRemoveMarket(env e, bytes data) {
    VaultV2.MarketParams marketParams = Utils.decodeMarketParams(data);
    uint256 assets = Utils.expectedSupplyAssets(e, Morpho, marketParams, MorphoMarketV1Adapter);

    // Need to require that all markets in marketParamsList are distinct.

    // Could also check that the deallocate call doesn't revert.
    deallocate(e, MorphoMarketV1Adapter, data, assets);

    uint256 i;
    // Is this needed ?
    require i < MorphoMarketV1Adapter.marketParamsListLength();
    address loanToken;
    address collateralToken;
    address oracle;
    address irm;
    uint256 lltv;
    (loanToken, collateralToken, oracle, irm, lltv) = MorphoMarketV1Adapter.marketParamsList(i);
    assert (
        loanToken != marketParams.loanToken ||
        collateralToken != marketParams.collateralToken ||
        oracle != marketParams.oracle ||
        irm != marketParams.irm ||
        lltv != marketParams.lltv
    );

}
