// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Morpho Association

using Utils as Utils;

methods {
    function allocation(Morpho.MarketParams) external returns (uint256) envfree;

    // Needed because linking fails.
    function _.transfer(address, uint256) external => DISPATCHER(true);
    function _.transferFrom(address, address, uint256) external => DISPATCHER(true);

    function _.borrowRate(Morpho.MarketParams, Morpho.Market) external => constantBorrowRate expect uint256;
    function _.borrowRateView(Morpho.MarketParams, Morpho.Market) external => constantBorrowRate expect uint256;

    function Utils.decodeMarketParams(bytes) external returns (Morpho.MarketParams) envfree;
}

// RUN : https://prover.certora.com/output/7508195/948a99f61d064f24832f12a43d0cd259/?anonymousKey=98b83d604d33896cec49c722a39aeee4694f56b7

persistent ghost uint256 constantBorrowRate;

function allocate_or_deallocate(bool allocate, env e, bytes data, uint256 assets, bytes4 selector, address sender) returns (bytes32[], int256) {
    bytes32[] ids;
    int256 change;

    if (allocate) {
        ids, change = allocate(e, data, assets, selector, sender);
    } else {
        ids, change = deallocate(e, data, assets, selector, sender);
    }
    
    return (ids, change);
}

// Check that allocating or deallocating zero assets returns an equivalent allocation change.  
rule sameChangeForAllocateAndDeallocateOnZeroAmount(env e, bytes data, bytes4 selector, address sender) {
  storage initialState = lastStorage;

  bytes32[] idsAllocate;
  int256 changeAllocate;
  idsAllocate, changeAllocate = allocate(e, data, 0, selector, sender);

  bytes32[] idsDeallocate;
  int256 changeDeallocate;
  idsDeallocate, changeDeallocate = deallocate(e, data, 0, selector, sender) at initialState;

  assert changeAllocate == changeDeallocate;
}


// Check that allocate or deallocate cannot return a change that would make the current allocation negative.
rule changeForAllocateOrDeallocateIsBoundedByAllocation(env e, bytes data, uint256 assets, bytes4 selector, address sender) {
  Morpho.MarketParams marketParams = Utils.decodeMarketParams(data);
  mathint allocation = allocation(marketParams);
  bool isAllocate;

  bytes32[] ids;
  int256 change;
  
  ids, change = allocate_or_deallocate(isAllocate, e, data, assets, selector, sender);

  assert allocation + change >= 0;
}


