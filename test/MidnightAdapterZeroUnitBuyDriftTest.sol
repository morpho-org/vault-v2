// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Morpho Association
pragma solidity ^0.8.0;

import "./MidnightAdapterTest.sol";

/// @dev Representation-agnostic simulation: only reads realAssets(), so the same file runs on main and on the prototype.
/// @dev Compares a position touched by repeated zero-unit buys (or zero-asset withdrawals) with the same position left untouched.
contract MidnightAdapterZeroUnitBuyDriftTest is MidnightAdapterTest {
    struct Drift {
        uint256 netCredit;
        uint256 startValue;
        uint256 maxDeficit;
        uint256 maxExcess;
        uint256 stalledTouched;
        uint256 stalledUntouched;
        uint256 finalDiff;
    }

    function priceForApr(uint256 apr, uint256 duration) internal pure returns (uint256) {
        return WAD * WAD / (WAD + apr * duration / 365 days);
    }

    function zeroUnitBuy(Offer memory offer) internal {
        offer.group = bytes32(vm.randomUint());
        offer.expiry = vm.getBlockTimestamp();
        bytes memory data = ratify([offer], signerAllocator);
        vm.prank(taker);
        midnight.take(offer, data, 0, taker, taker, address(0), "");
    }

    /// @dev mode 0: zero-unit buys, mode 1: zero-asset withdrawToVault.
    function simulate(uint256 assets, uint256 duration, uint256 apr, uint256 ops, uint256 interval, uint256 mode)
        internal
        returns (Drift memory d)
    {
        uint256 tick = TickLib.priceToTick(priceForApr(apr, duration), DEFAULT_TICK_SPACING);
        Offer memory offer = buy(duration, assets, tick);
        d.netCredit = adapter.marketData(_marketId(offer.market)).netCredit;
        d.startValue = adapter.realAssets();
        uint256[] memory touched = new uint256[](ops + 1);
        uint256 snapshot = vm.snapshotState();
        for (uint256 i; i < ops; i++) {
            skip(interval);
            if (mode == 0) zeroUnitBuy(offer);
            else withdrawToVault(offer.market, 0);
            touched[i] = adapter.realAssets();
        }
        vm.warp(offer.market.maturity);
        touched[ops] = adapter.realAssets();
        vm.revertToState(snapshot);
        uint256 previousTouched = d.startValue;
        uint256 previousUntouched = d.startValue;
        for (uint256 i; i <= ops; i++) {
            if (i < ops) skip(interval);
            else vm.warp(offer.market.maturity);
            uint256 untouched = adapter.realAssets();
            if (untouched > touched[i] && untouched - touched[i] > d.maxDeficit) d.maxDeficit = untouched - touched[i];
            if (touched[i] > untouched && touched[i] - untouched > d.maxExcess) d.maxExcess = touched[i] - untouched;
            if (touched[i] <= previousTouched) d.stalledTouched++;
            if (untouched <= previousUntouched) d.stalledUntouched++;
            previousTouched = touched[i];
            previousUntouched = untouched;
            if (i == ops) d.finalDiff = touched[i] > untouched ? touched[i] - untouched : untouched - touched[i];
        }
    }

    function report(string memory name, Drift memory d) internal pure {
        console.log(name);
        console.log("  netCredit, startValue", d.netCredit, d.startValue);
        console.log("  maxDeficit, maxExcess", d.maxDeficit, d.maxExcess);
        console.log("  stalled intervals touched, untouched", d.stalledTouched, d.stalledUntouched);
        console.log("  final diff at maturity", d.finalDiff);
    }

    function run(string memory name, uint256 assets, uint256 duration, uint256 apr, uint256 ops, uint256 mode)
        internal
    {
        runInterval(name, assets, duration, apr, ops, duration / (ops + 1), mode);
    }

    function runInterval(
        string memory name,
        uint256 assets,
        uint256 duration,
        uint256 apr,
        uint256 ops,
        uint256 interval,
        uint256 mode
    ) internal {
        deal(address(loanToken), address(parentVault), assets * 2);
        Drift memory d = simulate(assets, duration, apr, ops, interval, mode);
        report(name, d);
        assertEq(d.finalDiff, 0, "same value at maturity");
    }

    // Small WBTC positions (8 decimals).
    function testDriftWbtc0001Btc30d() public {
        run("WBTC 0.0001 BTC 30d 2% zero buys", 1e4, 30 days, 0.02e18, 1000, 0);
    }

    function testDriftWbtc001Btc30d() public {
        run("WBTC 0.001 BTC 30d 2% zero buys", 1e5, 30 days, 0.02e18, 1000, 0);
    }

    function testDriftWbtc001Btc365d() public {
        run("WBTC 0.001 BTC 365d 2% zero buys", 1e5, 365 days, 0.02e18, 1000, 0);
    }

    function testDriftWbtc1Btc365d() public {
        run("WBTC 1 BTC 365d 2% zero buys", 1e8, 365 days, 0.02e18, 1000, 0);
    }

    // USDC controls (6 decimals).
    function testDriftUsdc100Usdc30d() public {
        run("USDC 100 USDC 30d 5% zero buys", 100e6, 30 days, 0.05e18, 1000, 0);
    }

    function testDriftUsdc1mUsdc365d() public {
        run("USDC 1M USDC 365d 5% zero buys", 1e12, 365 days, 0.05e18, 1000, 0);
    }

    // 18-decimal controls.
    function testDrift18Dec1Token30d() public {
        run("18dec 1 token 30d 5% zero buys", 1e18, 30 days, 0.05e18, 1000, 0);
    }

    function testDrift18Dec1kToken365d() public {
        run("18dec 1k tokens 365d 5% zero buys", 1e21, 365 days, 0.05e18, 1000, 0);
    }

    // Zero-asset withdrawals: main keeps the rate, the prototype re-bases the stored value.
    function testDriftWithdrawWbtc001Btc30d() public {
        run("WBTC 0.001 BTC 30d 2% zero withdrawals", 1e5, 30 days, 0.02e18, 1000, 1);
    }

    function testDriftWithdrawUsdc100Usdc30d() public {
        run("USDC 100 USDC 30d 5% zero withdrawals", 100e6, 30 days, 0.05e18, 1000, 1);
    }

    function testDriftWithdraw18Dec1Token30d() public {
        run("18dec 1 token 30d 5% zero withdrawals", 1e18, 30 days, 0.05e18, 1000, 1);
    }

    // One zero-unit buy per minute for a day: interest per interval is far below one token unit for small WBTC.
    function testStallWbtc001BtcEveryMinute() public {
        runInterval("WBTC 0.001 BTC 30d 2% zero buy every minute for 1 day", 1e5, 30 days, 0.02e18, 1440, 60, 0);
    }

    function testStallWbtc1BtcEveryMinute() public {
        runInterval("WBTC 1 BTC 30d 2% zero buy every minute for 1 day", 1e8, 30 days, 0.02e18, 1440, 60, 0);
    }

    function testStallUsdc100UsdcEveryMinute() public {
        runInterval("USDC 100 USDC 30d 5% zero buy every minute for 1 day", 100e6, 30 days, 0.05e18, 1440, 60, 0);
    }

    function testStall18Dec1TokenEveryMinute() public {
        runInterval("18dec 1 token 30d 5% zero buy every minute for 1 day", 1e18, 30 days, 0.05e18, 1440, 60, 0);
    }

    /// @dev Many zero-unit buys in the same block.
    function testSameBlockZeroUnitBuys() public {
        uint256 duration = 30 days;
        uint256 tick = TickLib.priceToTick(priceForApr(0.02e18, duration), DEFAULT_TICK_SPACING);
        deal(address(loanToken), address(parentVault), 2e5);
        Offer memory offer = buy(duration, 1e5, tick);
        skip(duration / 3);
        uint256 before = adapter.realAssets();
        for (uint256 i; i < 200; i++) {
            zeroUnitBuy(offer);
        }
        console.log("same block: realAssets before, after 200 zero-unit buys", before, adapter.realAssets());
    }

    /* GAS (run with solc) */

    function realAssetsGas(uint256 marketCount) internal {
        for (uint256 i; i < marketCount; i++) {
            buy(1 days + i, 1e18);
        }
        vm.cool(address(adapter));
        uint256 gasBefore = gasleft();
        adapter.realAssets();
        console.log("realAssets gas, markets", gasBefore - gasleft(), marketCount);
    }

    function testGasRealAssets1Market() public {
        realAssetsGas(1);
    }

    function testGasRealAssets8Markets() public {
        realAssetsGas(8);
    }

    function testGasZeroUnitBuy() public {
        Offer memory offer = buy(30 days, 1e18);
        buy(31 days, 1e18);
        skip(1 days);
        offer.group = bytes32("zero buy");
        offer.expiry = vm.getBlockTimestamp();
        bytes memory data = ratify([offer], signerAllocator);
        vm.cool(address(adapter));
        vm.prank(taker);
        uint256 gasBefore = gasleft();
        midnight.take(offer, data, 0, taker, taker, address(0), "");
        console.log("zero-unit buy take gas, 2 markets", gasBefore - gasleft());
    }

    function testGasShortfallSale() public {
        Offer memory offer = buyAtDiscount(30 days, 100e18);
        buyAtDiscount(31 days, 100e18);
        setMinNetBuyRate(0);
        skip(1 days);
        vm.cool(address(adapter));
        uint256 gasBefore = gasleft();
        this.sellWithShortfall(offer.market, 1e15);
        console.log("shortfall sale gas, 2 markets", gasBefore - gasleft());
    }
}
