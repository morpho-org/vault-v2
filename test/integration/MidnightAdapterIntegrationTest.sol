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
import {TickLib, MAX_TICK} from "../../lib/midnight/src/libraries/TickLib.sol";
import {ORACLE_PRICE_SCALE} from "../../lib/morpho-blue/src/libraries/ConstantsLib.sol";

/// @dev Spec tests: full production flows of the MidnightAdapter, which only check that nothing reverts. Changes to this file require a human review (see .github/CODEOWNERS). Do not modify these tests to make a code change pass.
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

        _submitVaultChange(abi.encodeCall(IVaultV2.addAdapter, (address(adapter))));
        _submitVaultChange(abi.encodeCall(IVaultV2.setIsAllocator, (address(adapter), true)));
        _submitVaultChange(abi.encodeCall(IVaultV2.setForceDeallocatePenalty, (address(adapter), 0.02e18)));
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
        (Market memory market, uint256 units) = _buyAdapterForAssets(7 days, scale, "");
        vm.warp(market.maturity);
        _repay(market, units);
        vm.prank(allocator);
        adapter.withdrawToVault(market, units);
        uint256 shares = vault.balanceOf(depositor);
        vm.prank(depositor);
        vault.redeem(shares, depositor, depositor);
    }

    function testTakerBuy() public {
        Market memory market = _market(7 days);
        Offer memory offer = _externalOffer(market, false, scale);
        _supplyCollateral(borrower, market, scale);
        bytes memory ratifierData = _ratifyExternalOffer(offer);
        vm.prank(allocator);
        adapter.take(offer, ratifierData, scale, "");
    }

    function testTakerSell() public {
        (Market memory market,) = _buyAdapterForAssets(7 days, 2 * scale, "");
        Offer memory offer = _externalOffer(market, true, scale);
        bytes memory ratifierData = _ratifyExternalOffer(offer);
        vm.prank(allocator);
        adapter.take(offer, ratifierData, scale, "");
        vm.prank(depositor);
        vault.withdraw(scale, depositor, depositor);
    }

    function testMakerSell() public {
        (Market memory market,) = _buyAdapterForAssets(7 days, 2 * scale, "");
        Offer memory offer = _adapterBuyOffer(market, scale, "");
        offer.buy = false;
        offer.group = keccak256(abi.encode("sell", market.maturity, scale));
        offer.receiverIfMakerIsSeller = address(adapter);
        offer.reduceOnly = true;
        bytes memory ratifierData = _ratifyAdapterOffer(offer);
        deal(address(underlyingToken), lender, scale);
        vm.prank(lender);
        SafeERC20Lib.safeApprove(address(underlyingToken), address(midnight), scale);
        vm.prank(lender);
        midnight.take(offer, ratifierData, scale, lender, address(0), address(0), "");
    }

    function testForceDeallocate() public {
        (Market memory market,) = _buyAdapterForAssets(7 days, initialAssets, "");
        Offer memory offer = _externalOffer(market, true, scale);
        bytes memory ratifierData = _ratifyExternalOffer(offer);
        deal(address(underlyingToken), depositor, scale);
        vm.startPrank(depositor);
        SafeERC20Lib.safeApprove(address(underlyingToken), address(adapter), scale);
        vault.forceDeallocate(address(adapter), abi.encode(offer, ratifierData), scale, depositor);
        vault.withdraw(scale, depositor, depositor);
        vm.stopPrank();
    }

    function testSelfFundedBuy() public {
        (Market memory fundingMarket, uint256 units) = _buyAdapterForAssets(7 days, initialAssets, "");
        vm.warp(fundingMarket.maturity);
        _repay(fundingMarket, units);

        bytes memory callbackData = abi.encode(address(adapter), abi.encode(fundingMarket));
        _buyAdapterForAssets(30 days, scale, callbackData);
    }

    function _submitVaultChange(bytes memory data) internal {
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
        _submitVaultChange(abi.encodeCall(IVaultV2.increaseAbsoluteCap, (idData, type(uint128).max)));
        _submitVaultChange(abi.encodeCall(IVaultV2.increaseRelativeCap, (idData, 1e18)));
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

    function _adapterBuyOffer(Market memory market, uint256 maxUnits, bytes memory callbackData)
        internal
        view
        returns (Offer memory offer)
    {
        offer = Offer({
            market: market,
            buy: true,
            maker: address(adapter),
            start: block.timestamp,
            expiry: market.maturity,
            tick: MAX_TICK,
            group: keccak256(abi.encode(market.maturity, maxUnits)),
            callback: address(adapter),
            callbackData: callbackData,
            receiverIfMakerIsSeller: address(0),
            ratifier: address(adapter),
            reduceOnly: false,
            maxUnits: uint128(maxUnits),
            maxAssets: 0,
            continuousFeeCap: type(uint256).max
        });
    }

    function _externalOffer(Market memory market, bool buy, uint256 units) internal returns (Offer memory offer) {
        offer = Offer({
            market: market,
            buy: buy,
            maker: buy ? lender : borrower,
            start: block.timestamp,
            expiry: market.maturity,
            tick: MAX_TICK,
            group: keccak256(abi.encode("external", market.maturity, units, buy)),
            callback: address(0),
            callbackData: "",
            receiverIfMakerIsSeller: buy ? address(0) : borrower,
            ratifier: address(externalRatifier),
            reduceOnly: false,
            maxUnits: uint128(units),
            maxAssets: 0,
            continuousFeeCap: type(uint256).max
        });

        if (buy) {
            deal(address(underlyingToken), lender, units);
            vm.prank(lender);
            SafeERC20Lib.safeApprove(address(underlyingToken), address(midnight), type(uint256).max);
        }
    }

    function _ratifyExternalOffer(Offer memory offer) internal returns (bytes memory data) {
        bytes32 root = HashLib.hashOffer(offer);
        vm.startPrank(offer.maker);
        midnight.setIsAuthorized(address(externalRatifier), true, offer.maker);
        externalRatifier.setIsRootRatified(offer.maker, root, true);
        vm.stopPrank();
        bytes32[] memory proof = new bytes32[](0);
        data = abi.encode(root, uint256(0), proof);
    }

    function _ratifyAdapterOffer(Offer memory offer) internal returns (bytes memory data) {
        bytes32 root = HashLib.hashPriceRatifierV1Offer(offer, address(0));
        vm.prank(allocator);
        priceRatifier.setIsRootRatified(address(adapter), root, true);
        bytes32[] memory proof = new bytes32[](0);
        data = abi.encode(address(priceRatifier), abi.encode(root, 0, proof, address(0)));
    }

    function _buyAdapterForAssets(uint256 duration, uint256 assets, bytes memory callbackData)
        internal
        returns (Market memory market, uint256 units)
    {
        market = _market(duration);
        Offer memory offer = _adapterBuyOffer(market, type(uint128).max, callbackData);
        units = assets * 1e18 / TickLib.tickToPrice(offer.tick);
        if (units * TickLib.tickToPrice(offer.tick) / 1e18 < assets) units++;
        offer.maxUnits = uint128(units);
        bytes memory ratifierData = _ratifyAdapterOffer(offer);
        _supplyCollateral(borrower, market, units);
        vm.prank(borrower);
        midnight.take(offer, ratifierData, units, borrower, borrower, address(0), "");
    }

    function _supplyCollateral(address account, Market memory market, uint256 units) internal {
        uint256 collateral = units * 2e18 / scale;
        deal(address(collateralToken), account, collateral);
        vm.prank(account);
        collateralToken.approve(address(midnight), collateral);
        vm.prank(account);
        midnight.supplyCollateral(market, 0, collateral, account);
    }

    function _repay(Market memory market, uint256 units) internal {
        deal(address(underlyingToken), borrower, units);
        vm.prank(borrower);
        SafeERC20Lib.safeApprove(address(underlyingToken), address(midnight), units);
        vm.prank(borrower);
        midnight.repay(market, units, borrower, address(0), "");
    }
}
