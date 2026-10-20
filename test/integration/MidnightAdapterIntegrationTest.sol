// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Morpho Association
pragma solidity ^0.8.0;

import {BaseTest} from "../BaseTest.sol";
import {IMidnightAdapter, IMidnightAdapterBase} from "../../src/adapters/interfaces/IMidnightAdapter.sol";
import {IMidnightAdapterFactory} from "../../src/adapters/interfaces/IMidnightAdapterFactory.sol";
import {
    IMidnightAdapterPriceRatifierV1
} from "../../src/adapters/ratifiers/interfaces/IMidnightAdapterPriceRatifierV1.sol";
import {IVaultV2} from "../../src/interfaces/IVaultV2.sol";
import {SafeERC20Lib} from "../../src/libraries/SafeERC20Lib.sol";
import {WAD} from "../../src/libraries/ConstantsLib.sol";
import {ERC20Mock} from "../mocks/ERC20Mock.sol";
import {OracleMock} from "../../lib/morpho-blue/src/mocks/OracleMock.sol";
import {IMidnight, Market, Offer, CollateralParams} from "../../lib/midnight/src/interfaces/IMidnight.sol";
import {HashLib} from "../../lib/midnight/src/ratifiers/libraries/HashLib.sol";
import {ISetterRatifier} from "../../lib/midnight/src/ratifiers/interfaces/ISetterRatifier.sol";
import {IdLib} from "../../lib/midnight/src/libraries/IdLib.sol";
import {TickLib} from "../../lib/midnight/src/libraries/TickLib.sol";
import {ORACLE_PRICE_SCALE} from "../../lib/morpho-blue/src/libraries/ConstantsLib.sol";

/// @dev Spec tests: full production flows of the MidnightAdapter, which only check that nothing reverts. Changes to this file require a human review.
contract MidnightAdapterIntegrationTest is BaseTest {
    /// @dev Price of about 0.994 assets per unit.
    uint256 internal constant TICK = 4400;

    address internal depositor = makeAddr("depositor");
    address internal borrower = makeAddr("borrower");
    address internal lender = makeAddr("lender");

    IMidnight internal midnight;
    IMidnightAdapter internal adapter;
    IMidnightAdapterPriceRatifierV1 internal priceSubRatifier;
    ISetterRatifier internal setterRatifier;
    ERC20Mock internal collateralToken;
    OracleMock internal oracle;
    CollateralParams internal collateralParams;
    uint256 internal oneToken;
    uint256 internal initialAssets;

    function setUp() public override {
        vm.setEvmVersion("osaka");
        super.setUp();

        oneToken = 10 ** underlyingTokenDecimals;
        initialAssets = 100_000 * oneToken;

        vm.prank(owner);
        midnight = IMidnight(deployCode("Midnight.sol:Midnight"));
        vm.startPrank(owner);
        midnight.enableLltv(1e18);
        midnight.enableLiquidationCursor(0.25e18);
        vm.stopPrank();

        collateralToken = new ERC20Mock(18);
        oracle = new OracleMock();
        oracle.setPrice(ORACLE_PRICE_SCALE * oneToken / 1e18);
        collateralParams = CollateralParams(address(collateralToken), 1e18, 0.25e18, address(oracle));

        uint256[] memory durations = new uint256[](1);
        durations[0] = 7 days;
        IMidnightAdapterFactory factory = IMidnightAdapterFactory(
            deployCode("MidnightAdapterFactory.sol:MidnightAdapterFactory", abi.encode(address(midnight)))
        );
        adapter = IMidnightAdapter(factory.createMidnightAdapter(address(vault), durations, bytes32(0)));
        priceSubRatifier = IMidnightAdapterPriceRatifierV1(
            deployCode("MidnightAdapterPriceRatifierV1.sol:MidnightAdapterPriceRatifierV1")
        );
        setterRatifier = ISetterRatifier(deployCode("SetterRatifier.sol:SetterRatifier", abi.encode(address(midnight))));

        _submitAndSet(address(adapter), abi.encodeCall(IMidnightAdapterBase.increaseMaxTtm, (90 days)));

        _submitAndSet(address(vault), abi.encodeCall(IVaultV2.addAdapter, (address(adapter))));
        _submitAndSet(address(vault), abi.encodeCall(IVaultV2.setIsAllocator, (address(adapter), true)));
        _submitAndSet(address(vault), abi.encodeCall(IVaultV2.setForceDeallocatePenalty, (address(adapter), 0.02e18)));
        vm.prank(allocator);
        vault.setMaxRate(1e18 / uint256(365 days));
        vm.prank(allocator);
        adapter.setIsSubRatifier(address(priceSubRatifier), true);
        vm.prank(curator);
        adapter.setMaxNetSellRate(1e18 / uint256(365 days));

        _increaseCaps(abi.encode("this", address(adapter)));
        _increaseCaps(abi.encode("collateralToken", address(collateralToken)));
        _increaseCaps(abi.encode("collateralParams", collateralParams));
        _increaseCaps(abi.encode("enterGate", address(0)));
        _increaseCaps(abi.encode("liquidatorGate", address(0)));
        _increaseCaps(abi.encode("rcfThreshold", uint256(0)));
        _increaseCaps(abi.encode("this/duration", address(adapter), 7 days));

        deal(address(underlyingToken), depositor, initialAssets);
        vm.startPrank(depositor);
        SafeERC20Lib.safeApprove(address(underlyingToken), address(vault), initialAssets);
        vault.deposit(initialAssets, depositor);
        vm.stopPrank();
    }

    function testMakerBuy() public {
        uint256 units = initialAssets * WAD / TickLib.tickToPrice(TICK);
        Market memory market = _market(7 days);
        Offer memory offer = Offer({
            market: market,
            buy: true,
            maker: address(adapter),
            start: block.timestamp,
            expiry: market.maturity,
            tick: TICK,
            group: keccak256(abi.encode("buy", market.maturity, units)),
            callback: address(adapter),
            callbackData: abi.encode(address(0), ""),
            receiverIfMakerIsSeller: address(0),
            ratifier: address(adapter),
            reduceOnly: false,
            maxUnits: uint128(units),
            maxAssets: 0,
            continuousFeeCap: type(uint256).max
        });
        bytes32 root = HashLib.hashPriceRatifierV1Offer(offer, address(0));
        vm.prank(allocator);
        priceSubRatifier.setIsRootRatified(address(adapter), root, true);
        bytes32[] memory proof = new bytes32[](0);
        bytes memory ratifierData =
            abi.encode(address(priceSubRatifier), abi.encode(root, uint256(0), proof, address(0)));
        uint256 collateral = units * 2e18 / oneToken;
        deal(address(collateralToken), borrower, collateral);
        vm.startPrank(borrower);
        collateralToken.approve(address(midnight), collateral);
        midnight.supplyCollateral(market, 0, collateral, borrower);
        midnight.take(offer, ratifierData, units, borrower, borrower, address(0), "");
        vm.stopPrank();
    }

    function testRepayWithdrawRedeem() public {
        testMakerBuy();
        Market memory market = _market(7 days);
        uint256 units = initialAssets * WAD / TickLib.tickToPrice(TICK);
        vm.warp(market.maturity);
        deal(address(underlyingToken), borrower, units);
        vm.startPrank(borrower);
        SafeERC20Lib.safeApprove(address(underlyingToken), address(midnight), units);
        midnight.repay(market, units, borrower, address(0), "");
        vm.stopPrank();

        adapter.withdrawToVault(market, units);
        uint256 shares = vault.balanceOf(depositor);
        vm.startPrank(depositor);
        vault.redeem(shares, depositor, depositor);
        vm.stopPrank();
    }

    function testTakerBuy() public {
        Market memory market = _market(7 days);
        uint256 units = 1000 * oneToken;
        Offer memory offer = Offer({
            market: market,
            buy: false,
            maker: borrower,
            start: block.timestamp,
            expiry: market.maturity,
            tick: TICK,
            group: keccak256(abi.encode("external", market.maturity, units, false)),
            callback: address(0),
            callbackData: "",
            receiverIfMakerIsSeller: borrower,
            ratifier: address(setterRatifier),
            reduceOnly: false,
            maxUnits: uint128(units),
            maxAssets: 0,
            continuousFeeCap: type(uint256).max
        });
        uint256 collateral = units * 2e18 / oneToken;
        deal(address(collateralToken), borrower, collateral);
        bytes32 root = HashLib.hashOffer(offer);
        bytes32[] memory proof = new bytes32[](0);
        bytes memory ratifierData = abi.encode(root, uint256(0), proof);
        vm.startPrank(borrower);
        collateralToken.approve(address(midnight), collateral);
        midnight.supplyCollateral(market, 0, collateral, borrower);
        midnight.setIsAuthorized(address(setterRatifier), true, borrower);
        setterRatifier.setIsRootRatified(borrower, root, true);
        vm.stopPrank();

        vm.prank(allocator);
        adapter.take(offer, ratifierData, units, abi.encode(address(0), ""));
    }

    function testTakerSell() public {
        testMakerBuy();
        Market memory market = _market(7 days);

        uint256 units = 1000 * oneToken;
        Offer memory offer = Offer({
            market: market,
            buy: true,
            maker: lender,
            start: block.timestamp,
            expiry: market.maturity,
            tick: TICK,
            group: keccak256(abi.encode("external", market.maturity, units, true)),
            callback: address(0),
            callbackData: "",
            receiverIfMakerIsSeller: address(0),
            ratifier: address(setterRatifier),
            reduceOnly: false,
            maxUnits: uint128(units),
            maxAssets: 0,
            continuousFeeCap: type(uint256).max
        });
        deal(address(underlyingToken), lender, units);
        bytes32 root = HashLib.hashOffer(offer);
        bytes32[] memory proof = new bytes32[](0);
        bytes memory ratifierData = abi.encode(root, uint256(0), proof);
        vm.startPrank(lender);
        SafeERC20Lib.safeApprove(address(underlyingToken), address(midnight), type(uint256).max);
        midnight.setIsAuthorized(address(setterRatifier), true, lender);
        setterRatifier.setIsRootRatified(lender, root, true);
        vm.stopPrank();

        vm.prank(allocator);
        adapter.take(offer, ratifierData, units, "");
        // Only the sale's proceeds (price ~0.994) are idle.
        vm.prank(depositor);
        vault.withdraw(units * 99 / 100, depositor, depositor);
    }

    function testMakerSell() public {
        testMakerBuy();
        Market memory market = _market(7 days);

        uint256 units = 1000 * oneToken;
        Offer memory offer = Offer({
            market: market,
            buy: false,
            maker: address(adapter),
            start: block.timestamp,
            expiry: market.maturity,
            tick: TICK,
            group: keccak256(abi.encode("sell", market.maturity, units)),
            callback: address(adapter),
            callbackData: "",
            receiverIfMakerIsSeller: address(adapter),
            ratifier: address(adapter),
            reduceOnly: true,
            maxUnits: uint128(units),
            maxAssets: 0,
            continuousFeeCap: type(uint256).max
        });
        bytes32 root = HashLib.hashPriceRatifierV1Offer(offer, address(0));
        vm.prank(allocator);
        priceSubRatifier.setIsRootRatified(address(adapter), root, true);
        bytes32[] memory proof = new bytes32[](0);
        bytes memory ratifierData =
            abi.encode(address(priceSubRatifier), abi.encode(root, uint256(0), proof, address(0)));
        deal(address(underlyingToken), lender, units);
        vm.startPrank(lender);
        SafeERC20Lib.safeApprove(address(underlyingToken), address(midnight), units);
        midnight.take(offer, ratifierData, units, lender, address(0), address(0), "");
        vm.stopPrank();
        // Only the sale's proceeds (price ~0.994) are idle.
        vm.prank(depositor);
        vault.withdraw(units * 99 / 100, depositor, depositor);
    }

    function testForceSell() public {
        testMakerBuy();
        Market memory market = _market(7 days);
        _submitAndSet(address(adapter), abi.encodeCall(IMidnightAdapterBase.setForceSellable, (IdLib.toId(market))));

        uint256 units = 1000 * oneToken;
        Offer memory offer = Offer({
            market: market,
            buy: true,
            maker: lender,
            start: block.timestamp,
            expiry: market.maturity,
            tick: 0,
            group: keccak256(abi.encode("force sell", market.maturity, units)),
            callback: address(0),
            callbackData: "",
            receiverIfMakerIsSeller: address(0),
            ratifier: address(setterRatifier),
            reduceOnly: false,
            maxUnits: uint128(units),
            maxAssets: 0,
            continuousFeeCap: type(uint256).max
        });
        bytes32 root = HashLib.hashOffer(offer);
        bytes32[] memory proof = new bytes32[](0);
        bytes memory ratifierData = abi.encode(root, uint256(0), proof);
        vm.startPrank(lender);
        midnight.setIsAuthorized(address(setterRatifier), true, lender);
        setterRatifier.setIsRootRatified(lender, root, true);
        vm.stopPrank();

        vm.prank(allocator);
        adapter.take(offer, ratifierData, units, "");
    }

    function testForceDeallocate() public {
        testMakerBuy();
        Market memory market = _market(7 days);

        uint256 units = 1000 * oneToken;
        Offer memory offer = Offer({
            market: market,
            buy: true,
            maker: lender,
            start: block.timestamp,
            expiry: market.maturity,
            tick: TICK,
            group: keccak256(abi.encode("external", market.maturity, units, true)),
            callback: address(0),
            callbackData: "",
            receiverIfMakerIsSeller: address(0),
            ratifier: address(setterRatifier),
            reduceOnly: false,
            maxUnits: uint128(units),
            maxAssets: 0,
            continuousFeeCap: type(uint256).max
        });
        deal(address(underlyingToken), lender, units);
        bytes32 root = HashLib.hashOffer(offer);
        bytes32[] memory proof = new bytes32[](0);
        bytes memory ratifierData = abi.encode(root, uint256(0), proof);
        vm.startPrank(lender);
        SafeERC20Lib.safeApprove(address(underlyingToken), address(midnight), type(uint256).max);
        midnight.setIsAuthorized(address(setterRatifier), true, lender);
        setterRatifier.setIsRootRatified(lender, root, true);
        vm.stopPrank();

        uint256 sellerAssets = units * TickLib.tickToPrice(TICK) / WAD;
        deal(address(underlyingToken), depositor, units - sellerAssets);
        vm.startPrank(depositor);
        SafeERC20Lib.safeApprove(address(underlyingToken), address(adapter), units);
        vault.forceDeallocate(address(adapter), abi.encode(offer, ratifierData), units, depositor);
        vault.withdraw(units, depositor, depositor);
        vm.stopPrank();
    }

    function _submitAndSet(address target, bytes memory data) internal {
        vm.prank(curator);
        IVaultV2(target).submit(data);
        (bool success, bytes memory returnData) = target.call(data);
        if (!success) {
            assembly ("memory-safe") {
                revert(add(returnData, 32), mload(returnData))
            }
        }
    }

    function _increaseCaps(bytes memory idData) internal {
        _submitAndSet(address(vault), abi.encodeCall(IVaultV2.increaseAbsoluteCap, (idData, type(uint128).max)));
        _submitAndSet(address(vault), abi.encodeCall(IVaultV2.increaseRelativeCap, (idData, 1e18)));
    }

    function _market(uint256 duration) internal view returns (Market memory market) {
        CollateralParams[] memory collaterals = new CollateralParams[](1);
        collaterals[0] = collateralParams;
        market = Market({
            chainId: block.chainid,
            midnight: address(midnight),
            loanToken: address(underlyingToken),
            collateralParams: collaterals,
            maturity: block.timestamp + duration,
            rcfThreshold: 0,
            enterGate: address(0),
            liquidatorGate: address(0)
        });
    }
}
