// SPDX-License-Identifier: MIT
// Copyright (c) 2025 Morpho Association

// Methods entries for the specs whose conf links the adapter's midnight to the Midnight contract, and whose rules depend only on the calls and on the storage writes that the adapter and Midnight make.
methods {
    // Midnight's take calls onBuy on the callback of the buyer and onSell on the callback of the seller. When the callback is the adapter, the prover executes the adapter's function. When it is another contract, the call stays unresolved.
    function _.onBuy(bytes32, Midnight.Market, uint256, uint256, uint256, address, bytes) external => DISPATCHER(false);
    function _.onSell(bytes32, Midnight.Market, uint256, uint256, uint256, address, address, bytes) external => DISPATCHER(false);

    // These functions make no external call and do not write the storage of the adapter. NONDET replaces each of them with an arbitrary result, which makes the proof faster.
    function Midnight.touchMarket(Midnight.Market memory) internal returns (bytes32) => NONDET;
    function Midnight._updatePosition(Midnight.Market memory, bytes32, address) internal returns (uint128, uint128, uint128) => NONDET;
    function Midnight.settlementFee(bytes32, uint256) internal returns (uint256) => NONDET;
    function UtilsLib.tExchange(uint256, bytes32, address, bool) internal returns (bool) => NONDET;
    function TickLib.tickToPrice(uint256) internal returns (uint256) => NONDET;
    function UtilsLib.mulDivDown(uint256, uint256, uint256) internal returns (uint256) => NONDET;
    function UtilsLib.mulDivUp(uint256, uint256, uint256) internal returns (uint256) => NONDET;
    function IdLib.toId(MidnightAdapter.Market memory) internal returns (bytes32) => NONDET;
}
