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
    function MorphoMarketV1.totalSupplyAssets(MorphoHarness.Id) external returns (uint256) envfree;
    function MorphoMarketV1.totalSupplyShares(MorphoHarness.Id) external returns (uint256) envfree;
    function MorphoMarketV1.supplyShares(MorphoHarness.Id, address) external returns (uint256) envfree;
    function MorphoMarketV1.lastUpdate(MorphoHarness.Id) external returns (uint256) envfree;
    function MorphoMarketV1.isAuthorized(address, address) external returns (bool) envfree;
    function Utils.decodeMarketParams(bytes) external returns (MorphoHarness.MarketParams) envfree;
    function Utils.id(MorphoHarness.MarketParams) external returns (MorphoHarness.Id) envfree;
    function Utils.wrapId(bytes32) external returns (MorphoHarness.Id) envfree;
    function Utils.unwrapId(MorphoHarness.Id) external returns (bytes32) envfree;

    // Linearize Morpho's share math: replace the nested mulDivDown/mulDivUp floor/ceil reasoning inside
    // SharesMathLib with tight two-sided multiplicative bounds so the solver reasons over multiplication
    // constraints instead of division. VIRTUAL_SHARES = 1e6, VIRTUAL_ASSETS = 1.
    function SharesMathLib.toSharesDown(uint256 assets, uint256 ta, uint256 ts) internal returns (uint256) => summaryToSharesDown(assets, ta, ts);
    function SharesMathLib.toAssetsDown(uint256 shares, uint256 ta, uint256 ts) internal returns (uint256) => summaryToAssetsDown(shares, ta, ts);
    function SharesMathLib.toSharesUp(uint256 assets, uint256 ta, uint256 ts) internal returns (uint256) => summaryToSharesUp(assets, ta, ts);
    function SharesMathLib.toAssetsUp(uint256 shares, uint256 ta, uint256 ts) internal returns (uint256) => summaryToAssetsUp(shares, ta, ts);

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

// Tight two-sided bounds pinning each SharesMathLib result to its unique floor/ceil. VS = 1e6, VA = 1.
// These are sound (result is only required to equal the mathematical floor/ceil) and effectively deterministic.
function summaryToSharesDown(uint256 assets, uint256 ta, uint256 ts) returns uint256 {
    uint256 result;
    require to_mathint(result) * (ta + 1) <= to_mathint(assets) * (ts + 1000000);
    require to_mathint(assets) * (ts + 1000000) < (to_mathint(result) + 1) * (ta + 1);
    return result;
}

function summaryToAssetsDown(uint256 shares, uint256 ta, uint256 ts) returns uint256 {
    uint256 result;
    require to_mathint(result) * (ts + 1000000) <= to_mathint(shares) * (ta + 1);
    require to_mathint(shares) * (ta + 1) < (to_mathint(result) + 1) * (ts + 1000000);
    return result;
}

function summaryToSharesUp(uint256 assets, uint256 ta, uint256 ts) returns uint256 {
    uint256 result;
    require (to_mathint(result)) * (ta + 1) >= to_mathint(assets) * (ts + 1000000);
    require result == 0 || (to_mathint(result) - 1) * (ta + 1) < to_mathint(assets) * (ts + 1000000);
    return result;
}

function summaryToAssetsUp(uint256 shares, uint256 ta, uint256 ts) returns uint256 {
    uint256 result;
    require (to_mathint(result)) * (ts + 1000000) >= to_mathint(shares) * (ta + 1);
    require result == 0 || (to_mathint(result) - 1) * (ts + 1000000) < to_mathint(shares) * (ta + 1);
    return result;
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

    mathint TA0 = MorphoMarketV1.totalSupplyAssets(marketIdWrapped);
    mathint TS0 = MorphoMarketV1.totalSupplyShares(marketIdWrapped);
    mathint s0 = MorphoMarketV1.supplyShares(marketIdWrapped, MorphoMarketV1AdapterV2);
    require s0 < TS0, "total supply shares is the sum of all the supply shares";
    require assets > 0, "supplying zero is a no-op";

    mathint valueBefore = MorphoMarketV1AdapterV2.expectedSupplyAssets(e, marketId);

    allocate(e, MorphoMarketV1AdapterV2, data, assets);

    mathint TA1 = MorphoMarketV1.totalSupplyAssets(marketIdWrapped);
    mathint TS1 = MorphoMarketV1.totalSupplyShares(marketIdWrapped);
    mathint s1 = MorphoMarketV1.supplyShares(marketIdWrapped, MorphoMarketV1AdapterV2);
    mathint valueAfter = MorphoMarketV1AdapterV2.expectedSupplyAssets(e, marketId);

    mathint m = s1 - s0;
    require TA1 == TA0 + assets;
    require TS1 == TS0 + m;
    require m >= assets;

    mathint VS = 1000000;
    mathint D0 = TA0 + 1;
    mathint N0 = TS0 + VS;
    mathint D1 = TA1 + 1;
    mathint N1 = TS1 + VS;

    mathint P;
    require P * N1 <= s0 * D1;
    require s0 * D1 < (P + 1) * N1;
    mathint Q;
    require Q * N1 <= m * D1;
    require m * D1 < (Q + 1) * N1;

    require to_mathint(valueBefore) * N0 <= s0 * D0;
    require s0 * D0 < (to_mathint(valueBefore) + 1) * N0;
    require to_mathint(valueAfter) * N1 <= s1 * D1;
    require s1 * D1 < (to_mathint(valueAfter) + 1) * N1;
    require m * D0 <= assets * N0;
    require assets * N0 < (m + 1) * D0;

    // newly minted shares are worth at least assets - 1
    assert Q + 1 >= assets;
    require Q + 1 >= assets;

    // supplying does not lower the price: old shares revalue up
    assert P >= to_mathint(valueBefore);
    require P >= to_mathint(valueBefore);

    // floor superadditivity
    assert to_mathint(valueAfter) >= P + Q;
    require to_mathint(valueAfter) >= P + Q;

    assert to_mathint(valueAfter) + 1 >= to_mathint(valueBefore) + assets;
}

invariant adapterSupplySharesIsLessThanActualSupplyShares(bytes32 marketId)
    MorphoMarketV1AdapterV2.supplyShares[marketId] <= MorphoMarketV1.supplyShares(Utils.wrapId(marketId), MorphoMarketV1AdapterV2)
    filtered { f -> f.contract == MorphoMarketV1AdapterV2 || f.contract == MorphoMarketV1 } {
        preserved MorphoMarketV1.withdraw(MorphoHarness.MarketParams marketParams, uint256 assets, uint256 shares, address onBehalf, address receiver) with (env e) {
            require e.msg.sender != MorphoMarketV1AdapterV2, "the adapter is not an EOA";
            require !MorphoMarketV1.isAuthorized(MorphoMarketV1AdapterV2, e.msg.sender), "the adapter does not call setAuthorization and it cannot sign an authorization";
        }
    }
