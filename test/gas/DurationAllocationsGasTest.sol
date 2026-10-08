// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import "../../lib/forge-std/src/Test.sol";
import {IMidnight} from "../../lib/midnight/src/interfaces/IMidnight.sol";
import {IERC20} from "../../src/interfaces/IERC20.sol";
import {IMidnightAdapter} from "../../src/adapters/interfaces/IMidnightAdapter.sol";
import {ERC20Mock} from "../mocks/ERC20Mock.sol";
import {VaultV2Mock} from "../mocks/VaultV2Mock.sol";
import {MidnightAdapterCurrent} from "./MidnightAdapterCurrent.sol";
import {MidnightAdapterCached} from "./MidnightAdapterCached.sol";
import {MidnightAdapterMain} from "./MidnightAdapterMain.sol";

/// @dev Benchmarks three implementations of durationAllocations.
/// @dev Run with `FOUNDRY_ISOLATE=false forge test --match-contract DurationAllocationsGasTest -vv`.
/// @dev Isolate mode must be off: it makes every external call its own transaction, so storage is always cold.
/// @dev Each ROW log line is: markets, durations, maturityProfile, variant, coldGas, warmGas, resultHash.
contract DurationAllocationsGasTest is Test {
    IMidnight internal midnight;
    VaultV2Mock internal parentVault;

    uint256[] internal durationPool = [1 days, 7 days, 30 days, 90 days, 180 days, 270 days, 365 days, 730 days];
    uint256 internal sink;

    uint256 internal constant MARKET_IDS_SLOT = 6;
    uint256 internal constant MARKET_DATA_SLOT = 7;

    /// @dev Maturity profiles: how many of the configured durations each market covers.
    uint256 internal constant ALL_COVERED = 0;
    uint256 internal constant SPREAD = 1;
    uint256 internal constant NONE_COVERED = 2;

    function setUp() public {
        vm.setEvmVersion("osaka");

        midnight = IMidnight(deployCode("Midnight.sol:Midnight"));
        IERC20 loanToken = IERC20(address(new ERC20Mock(18)));
        parentVault = new VaultV2Mock(
            address(loanToken), makeAddr("owner"), makeAddr("curator"), makeAddr("allocator"), address(0)
        );
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

    /// @dev Calls the adapter's gas probe, which measures the internal call to durationAllocations.
    function probeGas(address adapter, uint256 durationsCount, bool warmStorageFirst) internal returns (uint256) {
        vm.cool(adapter);

        (bool success, bytes memory returnData) = adapter.call(
            abi.encodeWithSignature("gasDurationAllocations(uint256,bool)", durationsCount, warmStorageFirst)
        );
        require(success, "probe failed");

        return abi.decode(returnData, (uint256));
    }

    function benchmark(uint256 marketsCount, uint256 durationsCount, uint256 maturityProfile) internal {
        uint256[] memory durations = new uint256[](durationsCount);
        for (uint256 i; i < durationsCount; i++) {
            durations[i] = durationPool[i];
        }

        address[3] memory variants = [
            address(new MidnightAdapterCurrent(address(parentVault), address(midnight), durations)),
            address(new MidnightAdapterCached(address(parentVault), address(midnight), durations)),
            address(new MidnightAdapterMain(address(parentVault), address(midnight), durations))
        ];
        string[3] memory variantNames = ["current", "cached", "main"];

        for (uint256 variantIndex; variantIndex < 3; variantIndex++) {
            address variant = variants[variantIndex];
            populateMarkets(variant, marketsCount, durationsCount, maturityProfile);

            uint256 coldGas = probeGas(variant, durationsCount, false);
            uint256 warmGas = probeGas(variant, durationsCount, true);

            // The result hash lets the reader check that all variants agree.
            uint256[] memory allocations = IMidnightAdapter(variant).durationAllocations(durationsCount);
            sink += allocations[0];
            bytes32 resultHash = keccak256(abi.encode(allocations));

            console.log(
                "ROW,%d,%d,%s",
                marketsCount,
                durationsCount,
                string.concat(
                    vm.toString(maturityProfile),
                    ",",
                    variantNames[variantIndex],
                    ",",
                    vm.toString(coldGas),
                    ",",
                    vm.toString(warmGas),
                    ",",
                    vm.toString(resultHash)
                )
            );
        }
    }

    function benchmarkAllDurationsAndProfiles(uint256 marketsCount) internal {
        uint256[4] memory durationsCounts = [uint256(1), 2, 5, 8];

        for (uint256 i; i < durationsCounts.length; i++) {
            for (uint256 maturityProfile; maturityProfile < 3; maturityProfile++) {
                benchmark(marketsCount, durationsCounts[i], maturityProfile);
            }
        }
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
