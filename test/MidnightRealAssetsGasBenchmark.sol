// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import {MidnightAdapterTest} from "./MidnightAdapterTest.sol";
import {IMidnightAdapter} from "../src/adapters/interfaces/IMidnightAdapter.sol";
import {Market, Offer} from "../lib/midnight/src/interfaces/IMidnight.sol";
import {OracleMock} from "../lib/morpho-blue/src/mocks/OracleMock.sol";
import {ORACLE_PRICE_SCALE} from "../lib/morpho-blue/src/libraries/ConstantsLib.sol";
import {MAX_CONTINUOUS_FEE} from "../lib/midnight/src/libraries/ConstantsLib.sol";

contract MidnightRealAssetsGasBenchmark is MidnightAdapterTest {
    function testGasBaseline() public {
        benchmark(false);
    }

    function testGasShortCircuit() public {
        benchmark(true);
    }

    function benchmark(bool shortCircuit) internal {
        if (shortCircuit) {
            adapter = IMidnightAdapter(
                deployCode(
                    "MidnightAdapterShortCircuitGasBenchmark.sol:MidnightAdapterShortCircuitGasBenchmark",
                    abi.encode(address(parentVault), address(midnight), allDurations)
                )
            );
            vm.prank(signerAllocator);
            adapter.setIsSubRatifier(address(ecrecoverRatifier), true);
            storedOffer.maker = address(adapter);
            storedOffer.callback = address(adapter);
            storedOffer.ratifier = address(adapter);
            address[] memory adapters = new address[](2);
            adapters[0] = address(adapter);
            adapters[1] = address(extraAssetsAdapter);
            parentVault.setAdapters(adapters);
        }

        midnight.setDefaultContinuousFee(address(loanToken), MAX_CONTINUOUS_FEE);
        string memory variant = shortCircuit ? "shortcircuit" : "baseline";
        uint256[8] memory counts = [uint256(0), 1, 5, 10, 25, 50, 100, 250];
        Market[] memory markets = new Market[](250);
        uint256 filled;
        uint256 start = vm.getBlockTimestamp();
        for (uint256 c; c < counts.length; c++) {
            uint256 count = counts[c];
            while (filled < count) {
                Offer memory offer = buy(30 days + filled, 1e18, discountTick);
                markets[filled] = offer.market;
                filled++;
            }
            vm.warp(start + 15 days);
            uint256 expectedAssets;
            for (uint256 i; i < count; i++) {
                uint256 credit = adapter.netCredit(_marketId(markets[i]));
                expectedAssets += 1e18 + (credit - 1e18) * 15 days / (30 days + i);
            }
            assertApproxEqAbs(adapter.realAssets(), expectedAssets, count, "midpoint valuation");
            measure(variant, count, "unchanged");
            if (count > 0) {
                uint256 snapshot = vm.snapshotState();
                OracleMock(storedCollaterals[0].oracle).setPrice(ORACLE_PRICE_SCALE / 4);
                OracleMock(storedCollaterals[1].oracle).setPrice(ORACLE_PRICE_SCALE / 4);
                midnight.liquidate(markets[0], 0, 0, 0, taker, false, address(this), address(0), "");
                measure(variant, count, "one_loss");
                for (uint256 i = 1; i < count; i++) {
                    midnight.liquidate(markets[i], 0, 0, 0, taker, false, address(this), address(0), "");
                }
                measure(variant, count, "all_loss");
                assertTrue(vm.revertToState(snapshot));
            }
            vm.warp(start);
        }
    }

    function measure(string memory variant, uint256 count, string memory scenario) internal {
        address target = address(adapter);
        vm.cool(target);
        vm.cool(address(midnight));
        assertGt(target.code.length, 0);
        assertGt(address(midnight).code.length, 0);
        (uint256 cold, uint256 coldAssets) = this.measuredCall(target);
        (uint256 warm, uint256 warmAssets) = this.measuredCall(target);
        assertEq(coldAssets, warmAssets, "cold and warm valuations");
        emit log_string(string.concat(
                "GAS,",
                variant,
                ",",
                vm.toString(count),
                ",",
                scenario,
                ",",
                vm.toString(cold),
                ",",
                vm.toString(warm),
                ",",
                vm.toString(coldAssets)
            ));
    }

    function measuredCall(address target) external view returns (uint256 used, uint256 assets) {
        uint256 before = gasleft();
        assets = IMidnightAdapter(target).realAssets();
        used = before - gasleft();
    }
}
