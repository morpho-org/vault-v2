// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import "../../lib/forge-std/src/Test.sol";
import {IMidnight} from "../../lib/midnight/src/interfaces/IMidnight.sol";
import {IERC20} from "../../src/interfaces/IERC20.sol";
import {IMidnightAdapter} from "../../src/adapters/interfaces/IMidnightAdapter.sol";
import {ERC20Mock} from "../mocks/ERC20Mock.sol";
import {VaultV2Mock} from "../mocks/VaultV2Mock.sol";
import {MidnightAdapterForLoopUnchecked} from "./MidnightAdapterForLoopUnchecked.sol";
import {MidnightAdapterMain} from "./MidnightAdapterMain.sol";
import {MidnightAdapterMainUnchecked} from "./MidnightAdapterMainUnchecked.sol";

/// @dev Measures from a fresh call frame so the test contract's memory does not leak into the measurement.
contract GasProber {
    uint256 internal sink;

    function probe(IMidnightAdapter adapter, uint256 length) external returns (uint256 gasUsed) {
        sink += adapter.realAssets();

        gasUsed = gasleft();
        uint256[] memory allocations = adapter.durationAllocations(length);
        gasUsed = gasUsed - gasleft();

        sink += allocations[0];
    }
}

/// @dev Benchmarks three implementations of durationAllocations: the for-loop version with unchecked arithmetic, main as
/// is, and main with unchecked arithmetic.
/// @dev Run with `FOUNDRY_ISOLATE=false forge test --match-contract DurationAllocationsGasTest -vv`.
/// @dev Isolate mode must be off: it makes every external call its own transaction, so storage is always cold.
/// @dev Storage is warmed first, as the vault's accrueInterest does through realAssets before the buy callback runs.
/// @dev Prints one table per market count, with the gas of each variant and the deltas against unchecked main.
contract DurationAllocationsGasTest is Test {
    IMidnight internal midnight;
    VaultV2Mock internal parentVault;
    GasProber internal prober;

    uint256[] internal durationPool = [1 days, 7 days, 30 days, 90 days, 180 days, 270 days, 365 days, 730 days];

    uint256 internal constant MARKET_IDS_SLOT = 6;
    uint256 internal constant MARKET_DATA_SLOT = 7;

    /// @dev Maturity profiles: how many of the configured durations each market covers.
    uint256 internal constant ALL_COVERED = 0;
    uint256 internal constant SPREAD = 1;
    uint256 internal constant NONE_COVERED = 2;
    string[3] internal PROFILE_NAMES = ["all covered", "spread", "none covered"];

    function setUp() public {
        vm.setEvmVersion("osaka");

        midnight = IMidnight(deployCode("Midnight.sol:Midnight"));
        IERC20 loanToken = IERC20(address(new ERC20Mock(18)));
        parentVault = new VaultV2Mock(
            address(loanToken), makeAddr("owner"), makeAddr("curator"), makeAddr("allocator"), address(0)
        );
        prober = new GasProber();
    }

    /// @dev Writes marketIds and marketData directly into the adapter's storage.
    function populateMarkets(address adapter, uint256 marketsCount, uint256 durationsCount, uint256 maturityProfile)
        internal
    {
        vm.store(adapter, bytes32(MARKET_IDS_SLOT), bytes32(marketsCount));
        bytes32 marketIdsBase = keccak256(abi.encode(MARKET_IDS_SLOT));

        for (uint256 marketIndex; marketIndex < marketsCount; marketIndex++) {
            bytes32 marketId = keccak256(abi.encode("market", marketIndex));
            vm.store(adapter, bytes32(uint256(marketIdsBase) + marketIndex), marketId);

            uint256 coveredDurations;
            if (maturityProfile == ALL_COVERED) coveredDurations = durationsCount;
            else if (maturityProfile == SPREAD) coveredDurations = marketIndex % (durationsCount + 1);
            else coveredDurations = 0;

            uint256 timeToMaturity = coveredDurations == 0 ? 0 : durationPool[coveredDurations - 1];
            uint256 maturity = block.timestamp + timeToMaturity;
            uint256 netCredit = 1e18 + marketIndex;
            uint256 growth = 123;

            uint256 packedMarketData = netCredit | (growth << 128) | (maturity << 192) | (marketIndex << 240);
            vm.store(adapter, keccak256(abi.encode(marketId, MARKET_DATA_SLOT)), bytes32(packedMarketData));
        }
    }

    function benchmark(uint256 marketsCount, uint256 durationsCount, uint256 maturityProfile) internal {
        uint256[] memory durations = new uint256[](durationsCount);
        for (uint256 i; i < durationsCount; i++) {
            durations[i] = durationPool[i];
        }

        address[3] memory variants = [
            address(new MidnightAdapterForLoopUnchecked(address(parentVault), address(midnight), durations)),
            address(new MidnightAdapterMain(address(parentVault), address(midnight), durations)),
            address(new MidnightAdapterMainUnchecked(address(parentVault), address(midnight), durations))
        ];

        uint256[3] memory gasUsed;

        for (uint256 variantIndex; variantIndex < 3; variantIndex++) {
            address variant = variants[variantIndex];
            populateMarkets(variant, marketsCount, durationsCount, maturityProfile);

            gasUsed[variantIndex] = prober.probe(IMidnightAdapter(variant), durationsCount);
        }

        console.log(
            string.concat(
                padLeft(vm.toString(durationsCount), 9),
                "  ",
                padRight(PROFILE_NAMES[maturityProfile], 12),
                padLeft(vm.toString(gasUsed[0]), 10),
                padLeft(vm.toString(gasUsed[1]), 10),
                padLeft(vm.toString(gasUsed[2]), 10),
                padLeft(signedDelta(gasUsed[2], gasUsed[1]), 14),
                padLeft(signedDelta(gasUsed[0], gasUsed[2]), 14)
            )
        );
    }

    function benchmarkAllDurationsAndProfiles(uint256 marketsCount) internal {
        console.log("");
        console.log(string.concat("=== ", vm.toString(marketsCount), " markets ==="));
        console.log("durations  profile       for_loop      main  main_unch      unch-main  for_loop-unch");

        uint256[4] memory durationsCounts = [uint256(1), 2, 5, 8];

        for (uint256 i; i < durationsCounts.length; i++) {
            for (uint256 maturityProfile; maturityProfile < 3; maturityProfile++) {
                benchmark(marketsCount, durationsCounts[i], maturityProfile);
            }
        }
    }

    function signedDelta(uint256 value, uint256 baseline) internal pure returns (string memory) {
        if (value >= baseline) return string.concat("+", vm.toString(value - baseline));
        return string.concat("-", vm.toString(baseline - value));
    }

    function padLeft(string memory text, uint256 width) internal pure returns (string memory) {
        while (bytes(text).length < width) {
            text = string.concat(" ", text);
        }
        return text;
    }

    function padRight(string memory text, uint256 width) internal pure returns (string memory) {
        while (bytes(text).length < width) {
            text = string.concat(text, " ");
        }
        return text;
    }

    function testGas1Market() public {
        benchmarkAllDurationsAndProfiles(1);
    }

    function testGas10Markets() public {
        benchmarkAllDurationsAndProfiles(10);
    }

    function testGas50Markets() public {
        benchmarkAllDurationsAndProfiles(50);
    }

    function testGas250Markets() public {
        benchmarkAllDurationsAndProfiles(250);
    }
}
