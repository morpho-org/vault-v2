// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Morpho Association

// Supplying assets into a Morpho market through the adapter loses at most 1 asset to rounding:
// expectedSupplyAssets_after + 1 >= expectedSupplyAssets_before + assets, the guarantee the SharePriceAboveOne check provides.
// Interest accrual is pinned off by assuming lastUpdate == block.timestamp so the before/after values are comparable.

using MorphoMarketV1AdapterV2 as MorphoMarketV1AdapterV2;
using MorphoHarness as MorphoMarketV1;
using Utils as Utils;

methods {
    function allocation(bytes32) external returns (uint256) envfree;

    function MorphoMarketV1AdapterV2.ids(MorphoHarness.MarketParams) external returns (bytes32[]) envfree;
    function MorphoMarketV1AdapterV2.allocation(MorphoHarness.MarketParams) external returns (uint256) envfree;
    function MorphoMarketV1.totalSupplyShares(MorphoHarness.Id) external returns (uint256) envfree;
    function MorphoMarketV1.supplyShares(MorphoHarness.Id, address) external returns (uint256) envfree;
    function MorphoMarketV1.lastUpdate(MorphoHarness.Id) external returns (uint256) envfree;
    function MorphoMarketV1.isAuthorized(address, address) external returns (bool) envfree;
    function Utils.decodeMarketParams(bytes) external returns (MorphoHarness.MarketParams) envfree;
    function Utils.id(MorphoHarness.MarketParams) external returns (MorphoHarness.Id) envfree;
    function Utils.wrapId(bytes32) external returns (MorphoHarness.Id) envfree;
    function Utils.unwrapId(MorphoHarness.Id) external returns (bytes32) envfree;

    function _.borrowRateView(bytes32, MorphoHarness.Market memory, address) internal => constantBorrowRate expect(uint256);
    function _.borrowRate(MorphoHarness.MarketParams, MorphoHarness.Market) external => constantBorrowRate expect(uint256);

    function _.allocate(bytes data, uint256 assets, bytes4 bs, address a) external with(env e) => morphoMarketV1AdapterV2WrapperSummary(e, true, data, assets, bs, a) expect(bytes32[], int256);
    function _.deallocate(bytes data, uint256 assets, bytes4 bs, address a) external with(env e) => morphoMarketV1AdapterV2WrapperSummary(e, false, data, assets, bs, a) expect(bytes32[], int256);

    function _.position(MorphoHarness.Id, address) external => DISPATCHER;
    function _.market(MorphoHarness.Id) external => DISPATCHER;

    // Assume no reentrancy by requiring known token implementations and no callbacks.
    // This is sound because the full proof can be recovered by induction over the number of reentrancy calls.
    // The base case is when there is no reentrancy, which is what this specification file proves.

    function _.transfer(address, uint256) external => DISPATCHER(true);
    function _.transferFrom(address, address, uint256) external => DISPATCHER(true);

    function _.onMorphoSupply(uint256, bytes) external => NONDET;
    function _.onMorphoRepay(uint256, bytes) external => NONDET;
    function _.onMorphoSupplyCollateral(uint256, bytes) external => NONDET;
    function _.onMorphoLiquidate(uint256, bytes) external => NONDET;
    function _.onMorphoFlashLoan(uint256, bytes) external => NONDET;
}

definition max_int256() returns int256 = (2 ^ 255) - 1;

strong invariant allocationIsInt256(bytes32 id)
    allocation(id) <= max_int256();

persistent ghost uint256 constantBorrowRate;

persistent ghost int256 ghostChange;

function morphoMarketV1AdapterV2WrapperSummary(env e, bool isAllocateCall, bytes data, uint256 assets, bytes4 bs, address a) returns (bytes32[], int256) {
    bytes32[] ids;
    int256 change;

    if (isAllocateCall) {
        ids, change = MorphoMarketV1AdapterV2.allocate(e, data, assets, bs, a);
    } else {
        ids, change = MorphoMarketV1AdapterV2.deallocate(e, data, assets, bs, a);
    }
    require forall uint256 i. forall uint256 j. i < j && j < ids.length => ids[j] != ids[i], "proven in the distinctMarketV1Ids rule";
    ghostChange = change;

    return (ids, change);
}

rule supplyLossIsAtMostOneAsset(env e, bytes data, uint256 assets) {
    require MorphoMarketV1 == 0x10, "ack";
    require MorphoMarketV1AdapterV2 == 0x11, "ack";
    require currentContract == 0x12, "ack";

    MorphoHarness.MarketParams marketParams = Utils.decodeMarketParams(data);
    MorphoHarness.Id marketIdWrapped = Utils.id(marketParams);
    bytes32 marketId = Utils.unwrapId(marketIdWrapped);

    require MorphoMarketV1.lastUpdate(marketIdWrapped) == e.block.timestamp, "interest is already accrued";

    requireInvariant adapterSupplySharesIsLessThanActualSupplyShares(marketId);
    require MorphoMarketV1.supplyShares(marketIdWrapped, MorphoMarketV1AdapterV2) < MorphoMarketV1.totalSupplyShares(marketIdWrapped), "total supply shares is the sum of all the supply shares";
    require assets > 0, "supplying zero is a no-op";

    mathint valueBefore = MorphoMarketV1AdapterV2.expectedSupplyAssets(e, marketId);

    allocate(e, MorphoMarketV1AdapterV2, data, assets);

    mathint valueAfter = MorphoMarketV1AdapterV2.expectedSupplyAssets(e, marketId);

    assert valueAfter + 1 >= valueBefore + assets;
}

invariant adapterSupplySharesIsLessThanActualSupplyShares(bytes32 marketId)
    MorphoMarketV1AdapterV2.supplyShares[marketId] <= MorphoMarketV1.supplyShares(Utils.wrapId(marketId), MorphoMarketV1AdapterV2)
    filtered { f -> f.contract == MorphoMarketV1AdapterV2 || f.contract == MorphoMarketV1 } {
        preserved MorphoMarketV1.withdraw(MorphoHarness.MarketParams marketParams, uint256 assets, uint256 shares, address onBehalf, address receiver) with (env e) {
            require e.msg.sender != MorphoMarketV1AdapterV2, "the adapter is not an EOA";
            require !MorphoMarketV1.isAuthorized(MorphoMarketV1AdapterV2, e.msg.sender), "the adapter does not call setAuthorization and it cannot sign an authorization";
        }
    }
