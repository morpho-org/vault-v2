// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Morpho Association
pragma solidity ^0.8.0;

import {MidnightAdapterGasTest} from "./MidnightAdapterGasTest.sol";
import {IMidnightAdapter} from "../src/adapters/interfaces/IMidnightAdapter.sol";
import {IVaultV2} from "../src/interfaces/IVaultV2.sol";
import {Market, Offer} from "../lib/midnight/src/interfaces/IMidnight.sol";
import {MAX_TICK, TickLib} from "../lib/midnight/src/libraries/TickLib.sol";
import {console} from "../lib/forge-std/src/console.sol";
import {StdStorage, stdStorage} from "../lib/forge-std/src/StdStorage.sol";

contract MidnightAdapterGasBatchCaller {
    IMidnightAdapter internal immutable adapter;

    constructor(IMidnightAdapter adapter_) {
        adapter = adapter_;
    }

    function takeTwice(Offer memory firstOffer, Offer memory secondOffer)
        external
        returns (uint256 gasFirst, uint256 gasSecond)
    {
        uint256 beforeGas = gasleft();
        adapter.take(firstOffer, hex"", firstOffer.maxUnits, abi.encode(address(0), bytes("")));
        gasFirst = beforeGas - gasleft();

        beforeGas = gasleft();
        adapter.take(secondOffer, hex"", secondOffer.maxUnits, abi.encode(address(0), bytes("")));
        gasSecond = beforeGas - gasleft();
    }
}

contract MidnightAdapterValuationGasTest is MidnightAdapterGasTest {
    bytes32 internal constant CALLBACK_SUCCESS = keccak256("morpho.midnight.callbackSuccess");

    using stdStorage for StdStorage;

    address internal benchmarkBuyer = makeAddr("benchmark-buyer");

    function testValuationGasFixtures() public {
        uint256 maxMarkets = adapter.MAX_MARKETS();
        uint128[] memory lossFactors = new uint128[](maxMarkets);

        vm.pauseGasMetering();
        MidnightAdapterGasBatchCaller batchCaller = new MidnightAdapterGasBatchCaller(adapter);
        _submitAndSet(address(vault), abi.encodeCall(IVaultV2.setIsAllocator, (address(batchCaller), true)));
        vm.prank(curator);
        adapter.setMaxNetSellRate(type(uint64).max);
        for (uint256 i; i < maxMarkets; i++) {
            bytes32 marketId = adapter.marketIds(i);
            lossFactors[i] = midnight.lossFactor(marketId);
            _setLossFactor(marketId, 0);
        }
        vm.resumeGasMetering();
        _runFixture(batchCaller, 0, 1, "no bad debt");

        vm.pauseGasMetering();
        for (uint256 i; i < maxMarkets; i++) {
            _setLossFactor(adapter.marketIds(i), lossFactors[i]);
        }
        vm.resumeGasMetering();
        _runFixture(batchCaller, 2, 3, "unsynced bad debt");
    }

    function _runFixture(
        MidnightAdapterGasBatchCaller batchCaller,
        uint256 setupMarketIndex,
        uint256 benchmarkMarketIndex,
        string memory fixture
    ) internal {
        Market memory setupMarket = midnight.toMarket(adapter.marketIds(setupMarketIndex));
        Market memory benchmarkMarket = midnight.toMarket(adapter.marketIds(benchmarkMarketIndex));

        vm.pauseGasMetering();
        _prepareBuyer(benchmarkBuyer);
        Offer memory setupSale =
            _makeBuyOffer(setupMarket, 1e18, TickLib.priceToTick(0.5e18, 4), keccak256(abi.encode(fixture, "setup")));
        _take(setupSale);

        Offer memory firstBuy = _makeBorrowOffer(benchmarkMarket, 1e15, keccak256(abi.encode(fixture, "buy-1")));
        Offer memory secondBuy = _makeBorrowOffer(benchmarkMarket, 1e15, keccak256(abi.encode(fixture, "buy-2")));
        Offer memory shortfallSale = _makeBuyOffer(
            benchmarkMarket, 1e18, TickLib.priceToTick(0.5e18, 4), keccak256(abi.encode(fixture, "sale-shortfall"))
        );
        Offer memory parSale =
            _makeBuyOffer(benchmarkMarket, 1e18, MAX_TICK, keccak256(abi.encode(fixture, "sale-par")));

        vm.resumeGasMetering();
        vm.cool(address(adapter));
        vm.cool(address(vault));
        vm.cool(address(midnight));
        vm.cool(address(underlyingToken));
        vm.cool(address(collateralToken));
        vm.cool(address(batchCaller));
        uint256 beforeGas = gasleft();
        (bool success, bytes memory returnData) = address(adapter).staticcall(abi.encodeWithSignature("realAssets()"));
        _logGas(fixture, "realAssets", beforeGas - gasleft(), success, returnData);

        vm.warp(block.timestamp + 1);
        vm.cool(address(adapter));
        vm.cool(address(vault));
        vm.cool(address(midnight));
        vm.cool(address(underlyingToken));
        vm.cool(address(collateralToken));
        vm.cool(address(batchCaller));
        (uint256 gasFirst, uint256 gasSecond) = batchCaller.takeTwice(firstBuy, secondBuy);
        _logGas(fixture, "first buy", gasFirst, true, bytes(""));
        _logGas(fixture, "second buy", gasSecond, true, bytes(""));

        vm.cool(address(adapter));
        vm.cool(address(vault));
        vm.cool(address(midnight));
        vm.cool(address(underlyingToken));
        vm.cool(address(collateralToken));
        beforeGas = gasleft();
        (success, returnData) = _take(shortfallSale);
        _logGas(fixture, "shortfall sale", beforeGas - gasleft(), success, returnData);

        vm.cool(address(adapter));
        vm.cool(address(vault));
        vm.cool(address(midnight));
        vm.cool(address(underlyingToken));
        vm.cool(address(collateralToken));
        beforeGas = gasleft();
        (success, returnData) = _take(parSale);
        _logGas(fixture, "no-shortfall sale", beforeGas - gasleft(), success, returnData);
    }

    function _prepareBuyer(address buyer) internal {
        uint256 balance = 100e18;
        deal(address(underlyingToken), buyer, balance);
        vm.startPrank(buyer);
        underlyingToken.approve(address(midnight), type(uint256).max);
        midnight.setIsAuthorized(address(this), true, buyer);
        vm.stopPrank();
    }

    function _makeBorrowOffer(Market memory market, uint256 units, bytes32 group)
        internal
        returns (Offer memory offer)
    {
        offer = Offer({
            market: market,
            buy: false,
            maker: borrower,
            start: block.timestamp,
            expiry: market.maturity,
            tick: TICK,
            group: group,
            callback: address(0),
            callbackData: "",
            receiverIfMakerIsSeller: borrower,
            ratifier: address(this),
            reduceOnly: false,
            maxUnits: uint128(units),
            maxAssets: 0,
            continuousFeeCap: type(uint256).max
        });

        uint256 collateral = units * 2e18 / oneToken;
        deal(address(collateralToken), borrower, collateral);
        vm.startPrank(borrower);
        collateralToken.approve(address(midnight), collateral);
        midnight.supplyCollateral(market, 0, collateral, borrower);
        midnight.setIsAuthorized(address(this), true, borrower);
        vm.stopPrank();
    }

    function _makeBuyOffer(Market memory market, uint256 units, uint256 tick, bytes32 group)
        internal
        view
        returns (Offer memory offer)
    {
        offer = Offer({
            market: market,
            buy: true,
            maker: benchmarkBuyer,
            start: block.timestamp,
            expiry: market.maturity,
            tick: tick,
            group: group,
            callback: address(0),
            callbackData: "",
            receiverIfMakerIsSeller: address(0),
            ratifier: address(this),
            reduceOnly: false,
            maxUnits: uint128(units),
            maxAssets: 0,
            continuousFeeCap: type(uint256).max
        });
    }

    function _take(Offer memory offer) internal returns (bool success, bytes memory returnData) {
        bytes memory takerCallbackData = offer.buy ? bytes("") : abi.encode(address(0), bytes(""));
        vm.prank(allocator);
        try adapter.take(offer, "", offer.maxUnits, takerCallbackData) {
            return (true, bytes(""));
        } catch (bytes memory revertData) {
            return (false, revertData);
        }
    }

    function isRatified(Offer memory, bytes memory, address) external pure returns (bytes32) {
        return CALLBACK_SUCCESS;
    }

    function _setLossFactor(bytes32 marketId, uint128 lossFactor) internal {
        stdstore.enable_packed_slots()
            .target(address(midnight))
            .sig("lossFactor(bytes32)")
            .with_key(marketId)
            .checked_write(lossFactor);
    }

    function _logGas(
        string memory fixture,
        string memory operation,
        uint256 gasUsed,
        bool success,
        bytes memory returnData
    ) internal pure {
        if (success) {
            console.log(string.concat(fixture, " / ", operation), gasUsed);
        } else {
            console.log(string.concat(fixture, " / ", operation, " reverted"));
            console.logBytes(returnData);
        }
    }
}
