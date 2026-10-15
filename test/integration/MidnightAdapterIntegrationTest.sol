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
import {ERC20Mock} from "../mocks/ERC20Mock.sol";
import {OracleMock} from "../../lib/morpho-blue/src/mocks/OracleMock.sol";
import {IMidnight, Market, Offer, CollateralParams} from "../../lib/midnight/src/interfaces/IMidnight.sol";
import {HashLib} from "../../lib/midnight/src/ratifiers/libraries/HashLib.sol";
import {ISetterRatifier} from "../../lib/midnight/src/ratifiers/interfaces/ISetterRatifier.sol";
import {MAX_TICK} from "../../lib/midnight/src/libraries/TickLib.sol";
import {ORACLE_PRICE_SCALE} from "../../lib/morpho-blue/src/libraries/ConstantsLib.sol";

/// @dev Spec tests: full production flows of the MidnightAdapter, which only check that nothing reverts. Changes to this file require a human review (see .github/CODEOWNERS).
contract MidnightAdapterIntegrationTest is BaseTest {
    address internal depositor = makeAddr("depositor");
    address internal borrower = makeAddr("borrower");
    address internal lender = makeAddr("lender");

    IMidnight internal midnight;
    IMidnightAdapter internal adapter;
    IMidnightAdapterPriceRatifierV1 internal priceRatifier;
    ISetterRatifier internal externalRatifier;
    ERC20Mock internal collateralToken;
    OracleMock internal oracle;
    CollateralParams internal collateralParams;
    uint256 internal scale;
    uint256 internal initialAssets;

    function setUp() public override {
        vm.setEvmVersion("osaka");
        super.setUp();

        scale = 10 ** underlyingTokenDecimals;
        initialAssets = 10 * scale;

        vm.prank(owner);
        midnight = IMidnight(deployCode("Midnight.sol:Midnight"));
        vm.startPrank(owner);
        midnight.enableLltv(1e18);
        midnight.enableLiquidationCursor(0.25e18);
        vm.stopPrank();

        collateralToken = new ERC20Mock(18);
        oracle = new OracleMock();
        oracle.setPrice(ORACLE_PRICE_SCALE * scale / 1e18);
        collateralParams = CollateralParams(address(collateralToken), 1e18, 0.25e18, address(oracle));

        uint256[] memory durations = new uint256[](2);
        durations[0] = 7 days;
        durations[1] = 30 days;
        IMidnightAdapterFactory factory = IMidnightAdapterFactory(
            deployCode("MidnightAdapterFactory.sol:MidnightAdapterFactory", abi.encode(address(midnight)))
        );
        adapter = IMidnightAdapter(factory.createMidnightAdapter(address(vault), durations, bytes32(0)));
        priceRatifier = IMidnightAdapterPriceRatifierV1(
            deployCode("MidnightAdapterPriceRatifierV1.sol:MidnightAdapterPriceRatifierV1")
        );
        externalRatifier =
            ISetterRatifier(deployCode("SetterRatifier.sol:SetterRatifier", abi.encode(address(midnight))));

        vm.prank(curator);
        adapter.submit(abi.encodeCall(IMidnightAdapterBase.increaseMaxTtm, (90 days)));
        vm.prank(curator);
        adapter.increaseMaxTtm(90 days);

        _submitAndSetVaultChange(abi.encodeCall(IVaultV2.addAdapter, (address(adapter))));
        _submitAndSetVaultChange(abi.encodeCall(IVaultV2.setIsAllocator, (address(adapter), true)));
        _submitAndSetVaultChange(abi.encodeCall(IVaultV2.setForceDeallocatePenalty, (address(adapter), 0.02e18)));
        vm.prank(allocator);
        vault.setMaxRate(1e18 / uint256(365 days));
        vm.prank(allocator);
        adapter.setIsSubRatifier(address(priceRatifier), true);

        _increaseCaps(abi.encode("this", address(adapter)));
        _increaseCaps(abi.encode("collateralToken", address(collateralToken)));
        _increaseCaps(abi.encode("collateralParams", collateralParams));
        _increaseCaps(abi.encode("enterGate", address(0)));
        _increaseCaps(abi.encode("liquidatorGate", address(0)));
        _increaseCaps(abi.encode("rcfThreshold", uint256(0)));
        _increaseCaps(abi.encode("this/duration", address(adapter), 7 days));
        _increaseCaps(abi.encode("this/duration", address(adapter), 30 days));

        deal(address(underlyingToken), depositor, initialAssets);
        vm.startPrank(depositor);
        SafeERC20Lib.safeApprove(address(underlyingToken), address(vault), initialAssets);
        vault.deposit(initialAssets, depositor);
        vm.stopPrank();
    }

    function testMakerBuyRepayWithdrawRedeem() public {
        uint256 units = scale;
        Market memory market = _market(7 days);
        Offer memory offer = Offer({
            market: market,
            buy: true,
            maker: address(adapter),
            start: block.timestamp,
            expiry: market.maturity,
            tick: MAX_TICK,
            group: keccak256(abi.encode(market.maturity, type(uint128).max)),
            callback: address(adapter),
            callbackData: "",
            receiverIfMakerIsSeller: address(0),
            ratifier: address(adapter),
            reduceOnly: false,
            maxUnits: uint128(units),
            maxAssets: 0,
            continuousFeeCap: type(uint256).max
        });
        bytes32 root = HashLib.hashPriceRatifierV1Offer(offer, address(0));
        vm.prank(allocator);
        priceRatifier.setIsRootRatified(address(adapter), root, true);
        bytes32[] memory proof = new bytes32[](0);
        bytes memory ratifierData = abi.encode(address(priceRatifier), abi.encode(root, uint256(0), proof, address(0)));
        uint256 collateral = units * 2e18 / scale;
        deal(address(collateralToken), borrower, collateral);
        vm.startPrank(borrower);
        collateralToken.approve(address(midnight), collateral);
        midnight.supplyCollateral(market, 0, collateral, borrower);
        midnight.take(offer, ratifierData, units, borrower, borrower, address(0), "");
        vm.stopPrank();

        vm.warp(market.maturity);
        deal(address(underlyingToken), borrower, units);
        vm.startPrank(borrower);
        SafeERC20Lib.safeApprove(address(underlyingToken), address(midnight), units);
        midnight.repay(market, units, borrower, address(0), "");
        vm.stopPrank();

        vm.prank(allocator);
        adapter.withdrawToVault(market, units);
        uint256 shares = vault.balanceOf(depositor);
        vm.startPrank(depositor);
        vault.redeem(shares, depositor, depositor);
        vm.stopPrank();
    }

    function testTakerBuy() public {
        Market memory market = _market(7 days);
        uint256 units = scale;
        Offer memory offer = Offer({
            market: market,
            buy: false,
            maker: borrower,
            start: block.timestamp,
            expiry: market.maturity,
            tick: MAX_TICK,
            group: keccak256(abi.encode("external", market.maturity, units, false)),
            callback: address(0),
            callbackData: "",
            receiverIfMakerIsSeller: borrower,
            ratifier: address(externalRatifier),
            reduceOnly: false,
            maxUnits: uint128(units),
            maxAssets: 0,
            continuousFeeCap: type(uint256).max
        });
        uint256 collateral = units * 2e18 / scale;
        deal(address(collateralToken), borrower, collateral);
        bytes32 root = HashLib.hashOffer(offer);
        bytes32[] memory proof = new bytes32[](0);
        bytes memory ratifierData = abi.encode(root, uint256(0), proof);
        vm.startPrank(borrower);
        collateralToken.approve(address(midnight), collateral);
        midnight.supplyCollateral(market, 0, collateral, borrower);
        midnight.setIsAuthorized(address(externalRatifier), true, borrower);
        externalRatifier.setIsRootRatified(borrower, root, true);
        vm.stopPrank();

        vm.prank(allocator);
        adapter.take(offer, ratifierData, units, "");
    }

    function testTakerSell() public {
        uint256 initialUnits = 2 * scale;
        Market memory market = _market(7 days);
        Offer memory adapterBuyOffer = Offer({
            market: market,
            buy: true,
            maker: address(adapter),
            start: block.timestamp,
            expiry: market.maturity,
            tick: MAX_TICK,
            group: keccak256(abi.encode(market.maturity, type(uint128).max)),
            callback: address(adapter),
            callbackData: "",
            receiverIfMakerIsSeller: address(0),
            ratifier: address(adapter),
            reduceOnly: false,
            maxUnits: uint128(initialUnits),
            maxAssets: 0,
            continuousFeeCap: type(uint256).max
        });
        bytes32 adapterRoot = HashLib.hashPriceRatifierV1Offer(adapterBuyOffer, address(0));
        vm.prank(allocator);
        priceRatifier.setIsRootRatified(address(adapter), adapterRoot, true);
        bytes32[] memory adapterProof = new bytes32[](0);
        bytes memory adapterRatifierData =
            abi.encode(address(priceRatifier), abi.encode(adapterRoot, uint256(0), adapterProof, address(0)));
        uint256 collateral = initialUnits * 2e18 / scale;
        deal(address(collateralToken), borrower, collateral);
        vm.startPrank(borrower);
        collateralToken.approve(address(midnight), collateral);
        midnight.supplyCollateral(market, 0, collateral, borrower);
        midnight.take(adapterBuyOffer, adapterRatifierData, initialUnits, borrower, borrower, address(0), "");
        vm.stopPrank();

        uint256 units = scale;
        Offer memory offer = Offer({
            market: market,
            buy: true,
            maker: lender,
            start: block.timestamp,
            expiry: market.maturity,
            tick: MAX_TICK,
            group: keccak256(abi.encode("external", market.maturity, units, true)),
            callback: address(0),
            callbackData: "",
            receiverIfMakerIsSeller: address(0),
            ratifier: address(externalRatifier),
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
        midnight.setIsAuthorized(address(externalRatifier), true, lender);
        externalRatifier.setIsRootRatified(lender, root, true);
        vm.stopPrank();

        vm.prank(allocator);
        adapter.take(offer, ratifierData, units, "");
        vm.prank(depositor);
        vault.withdraw(units, depositor, depositor);
    }

    function testMakerSell() public {
        uint256 initialUnits = 2 * scale;
        Market memory market = _market(7 days);
        Offer memory adapterBuyOffer = Offer({
            market: market,
            buy: true,
            maker: address(adapter),
            start: block.timestamp,
            expiry: market.maturity,
            tick: MAX_TICK,
            group: keccak256(abi.encode(market.maturity, type(uint128).max)),
            callback: address(adapter),
            callbackData: "",
            receiverIfMakerIsSeller: address(0),
            ratifier: address(adapter),
            reduceOnly: false,
            maxUnits: uint128(initialUnits),
            maxAssets: 0,
            continuousFeeCap: type(uint256).max
        });
        bytes32 adapterRoot = HashLib.hashPriceRatifierV1Offer(adapterBuyOffer, address(0));
        vm.prank(allocator);
        priceRatifier.setIsRootRatified(address(adapter), adapterRoot, true);
        bytes32[] memory adapterProof = new bytes32[](0);
        bytes memory adapterRatifierData =
            abi.encode(address(priceRatifier), abi.encode(adapterRoot, uint256(0), adapterProof, address(0)));
        uint256 collateral = initialUnits * 2e18 / scale;
        deal(address(collateralToken), borrower, collateral);
        vm.startPrank(borrower);
        collateralToken.approve(address(midnight), collateral);
        midnight.supplyCollateral(market, 0, collateral, borrower);
        midnight.take(adapterBuyOffer, adapterRatifierData, initialUnits, borrower, borrower, address(0), "");
        vm.stopPrank();

        uint256 units = scale;
        Offer memory offer = Offer({
            market: market,
            buy: false,
            maker: address(adapter),
            start: block.timestamp,
            expiry: market.maturity,
            tick: MAX_TICK,
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
        priceRatifier.setIsRootRatified(address(adapter), root, true);
        bytes32[] memory proof = new bytes32[](0);
        bytes memory ratifierData = abi.encode(address(priceRatifier), abi.encode(root, uint256(0), proof, address(0)));
        deal(address(underlyingToken), lender, units);
        vm.startPrank(lender);
        SafeERC20Lib.safeApprove(address(underlyingToken), address(midnight), units);
        midnight.take(offer, ratifierData, units, lender, address(0), address(0), "");
        vm.stopPrank();
    }

    function testForceDeallocate() public {
        uint256 initialUnits = initialAssets;
        Market memory market = _market(7 days);
        Offer memory adapterBuyOffer = Offer({
            market: market,
            buy: true,
            maker: address(adapter),
            start: block.timestamp,
            expiry: market.maturity,
            tick: MAX_TICK,
            group: keccak256(abi.encode(market.maturity, type(uint128).max)),
            callback: address(adapter),
            callbackData: "",
            receiverIfMakerIsSeller: address(0),
            ratifier: address(adapter),
            reduceOnly: false,
            maxUnits: uint128(initialUnits),
            maxAssets: 0,
            continuousFeeCap: type(uint256).max
        });
        bytes32 adapterRoot = HashLib.hashPriceRatifierV1Offer(adapterBuyOffer, address(0));
        vm.prank(allocator);
        priceRatifier.setIsRootRatified(address(adapter), adapterRoot, true);
        bytes32[] memory adapterProof = new bytes32[](0);
        bytes memory adapterRatifierData =
            abi.encode(address(priceRatifier), abi.encode(adapterRoot, uint256(0), adapterProof, address(0)));
        uint256 collateral = initialUnits * 2e18 / scale;
        deal(address(collateralToken), borrower, collateral);
        vm.startPrank(borrower);
        collateralToken.approve(address(midnight), collateral);
        midnight.supplyCollateral(market, 0, collateral, borrower);
        midnight.take(adapterBuyOffer, adapterRatifierData, initialUnits, borrower, borrower, address(0), "");
        vm.stopPrank();

        uint256 units = scale;
        Offer memory offer = Offer({
            market: market,
            buy: true,
            maker: lender,
            start: block.timestamp,
            expiry: market.maturity,
            tick: MAX_TICK,
            group: keccak256(abi.encode("external", market.maturity, units, true)),
            callback: address(0),
            callbackData: "",
            receiverIfMakerIsSeller: address(0),
            ratifier: address(externalRatifier),
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
        midnight.setIsAuthorized(address(externalRatifier), true, lender);
        externalRatifier.setIsRootRatified(lender, root, true);
        vm.stopPrank();

        deal(address(underlyingToken), depositor, units);
        vm.startPrank(depositor);
        SafeERC20Lib.safeApprove(address(underlyingToken), address(adapter), units);
        vault.forceDeallocate(address(adapter), abi.encode(offer, ratifierData), units, depositor);
        vault.withdraw(units, depositor, depositor);
        vm.stopPrank();
    }

    function testSelfFundedBuy() public {
        uint256 initialUnits = initialAssets;
        Market memory fundingMarket = _market(7 days);
        Offer memory fundingOffer = Offer({
            market: fundingMarket,
            buy: true,
            maker: address(adapter),
            start: block.timestamp,
            expiry: fundingMarket.maturity,
            tick: MAX_TICK,
            group: keccak256(abi.encode(fundingMarket.maturity, type(uint128).max)),
            callback: address(adapter),
            callbackData: "",
            receiverIfMakerIsSeller: address(0),
            ratifier: address(adapter),
            reduceOnly: false,
            maxUnits: uint128(initialUnits),
            maxAssets: 0,
            continuousFeeCap: type(uint256).max
        });
        bytes32 fundingRoot = HashLib.hashPriceRatifierV1Offer(fundingOffer, address(0));
        vm.prank(allocator);
        priceRatifier.setIsRootRatified(address(adapter), fundingRoot, true);
        bytes32[] memory fundingProof = new bytes32[](0);
        bytes memory fundingRatifierData =
            abi.encode(address(priceRatifier), abi.encode(fundingRoot, uint256(0), fundingProof, address(0)));
        uint256 fundingCollateral = initialUnits * 2e18 / scale;
        deal(address(collateralToken), borrower, fundingCollateral);
        vm.startPrank(borrower);
        collateralToken.approve(address(midnight), fundingCollateral);
        midnight.supplyCollateral(fundingMarket, 0, fundingCollateral, borrower);
        midnight.take(fundingOffer, fundingRatifierData, initialUnits, borrower, borrower, address(0), "");
        vm.stopPrank();

        vm.warp(fundingMarket.maturity);
        deal(address(underlyingToken), borrower, initialUnits);
        vm.startPrank(borrower);
        SafeERC20Lib.safeApprove(address(underlyingToken), address(midnight), initialUnits);
        midnight.repay(fundingMarket, initialUnits, borrower, address(0), "");
        vm.stopPrank();

        uint256 units = scale;
        bytes memory callbackData = abi.encode(address(adapter), abi.encode(fundingMarket));
        Market memory market = _market(30 days);
        Offer memory offer = Offer({
            market: market,
            buy: true,
            maker: address(adapter),
            start: block.timestamp,
            expiry: market.maturity,
            tick: MAX_TICK,
            group: keccak256(abi.encode(market.maturity, type(uint128).max)),
            callback: address(adapter),
            callbackData: callbackData,
            receiverIfMakerIsSeller: address(0),
            ratifier: address(adapter),
            reduceOnly: false,
            maxUnits: uint128(units),
            maxAssets: 0,
            continuousFeeCap: type(uint256).max
        });
        bytes32 root = HashLib.hashPriceRatifierV1Offer(offer, address(0));
        vm.prank(allocator);
        priceRatifier.setIsRootRatified(address(adapter), root, true);
        bytes32[] memory proof = new bytes32[](0);
        bytes memory ratifierData = abi.encode(address(priceRatifier), abi.encode(root, uint256(0), proof, address(0)));
        uint256 collateral = units * 2e18 / scale;
        deal(address(collateralToken), borrower, collateral);
        vm.startPrank(borrower);
        collateralToken.approve(address(midnight), collateral);
        midnight.supplyCollateral(market, 0, collateral, borrower);
        midnight.take(offer, ratifierData, units, borrower, borrower, address(0), "");
        vm.stopPrank();
    }

    function _submitAndSetVaultChange(bytes memory data) internal {
        vm.prank(curator);
        vault.submit(data);
        vm.prank(curator);
        (bool success, bytes memory returnData) = address(vault).call(data);
        if (!success) {
            assembly ("memory-safe") {
                revert(add(returnData, 32), mload(returnData))
            }
        }
    }

    function _increaseCaps(bytes memory idData) internal {
        _submitAndSetVaultChange(abi.encodeCall(IVaultV2.increaseAbsoluteCap, (idData, type(uint128).max)));
        _submitAndSetVaultChange(abi.encodeCall(IVaultV2.increaseRelativeCap, (idData, 1e18)));
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
