// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Morpho Association
pragma solidity ^0.8.0;

import {BaseTest} from "./BaseTest.sol";
import {Vm} from "../lib/forge-std/src/Vm.sol";
import {IMidnightAdapter, IMidnightAdapterBase, MarketData} from "../src/adapters/interfaces/IMidnightAdapter.sol";
import {IMidnightAdapterFactory} from "../src/adapters/interfaces/IMidnightAdapterFactory.sol";
import {
    IMidnightAdapterPriceRatifierV1
} from "../src/adapters/ratifiers/interfaces/IMidnightAdapterPriceRatifierV1.sol";
import {IERC20} from "../src/interfaces/IERC20.sol";
import {IVaultV2} from "../src/interfaces/IVaultV2.sol";
import {SafeERC20Lib} from "../src/libraries/SafeERC20Lib.sol";
import {
    MAX_FORCE_DEALLOCATE_PENALTY,
    MAX_MAX_RATE,
    MAX_MANAGEMENT_FEE,
    MAX_PERFORMANCE_FEE,
    WAD
} from "../src/libraries/ConstantsLib.sol";
import {ERC20Mock} from "./mocks/ERC20Mock.sol";
import {OracleMock} from "../lib/morpho-blue/src/mocks/OracleMock.sol";
import {IMorpho} from "../lib/morpho-blue/src/interfaces/IMorpho.sol";
import {IMorphoFlashLoanCallback} from "../lib/morpho-blue/src/interfaces/IMorphoCallbacks.sol";
import {IMidnight, Market, Offer, CollateralParams} from "../lib/midnight/src/interfaces/IMidnight.sol";
import {HashLib} from "../lib/midnight/src/ratifiers/libraries/HashLib.sol";
import {ISetterRatifier} from "../lib/midnight/src/ratifiers/interfaces/ISetterRatifier.sol";
import {MAX_TICK, TickLib} from "../lib/midnight/src/libraries/TickLib.sol";
import {ORACLE_PRICE_SCALE} from "../lib/morpho-blue/src/libraries/ConstantsLib.sol";

contract WorstCaseForceDeallocator {
    Vm private constant vm = Vm(address(uint160(uint256(keccak256("hevm cheat code")))));

    function forceDeallocate(
        FlashLoanForceDeallocator exiter,
        IVaultV2 vault,
        address adapter,
        bytes memory data,
        uint256 assets,
        address onBehalf,
        address caller,
        uint256 gas
    ) external {
        vm.prank(caller, caller);
        exiter.forceDeallocate{gas: gas}(vault, adapter, data, assets, onBehalf);
    }
}

contract FlashLoanForceDeallocator is IMorphoFlashLoanCallback {
    IMorpho internal immutable morpho;

    constructor(IMorpho morpho_) {
        morpho = morpho_;
    }

    function forceDeallocate(IVaultV2 vault, address adapter, bytes memory data, uint256 assets, address onBehalf)
        external
    {
        address asset = vault.asset();
        SafeERC20Lib.safeApprove(asset, adapter, type(uint256).max);
        SafeERC20Lib.safeApprove(asset, IMidnightAdapter(adapter).midnight(), type(uint256).max);
        SafeERC20Lib.safeApprove(asset, address(morpho), type(uint256).max);

        morpho.flashLoan(asset, assets, abi.encode(vault, adapter, data, onBehalf, msg.sender));
    }

    function onMorphoFlashLoan(uint256 assets, bytes calldata data) external override {
        require(msg.sender == address(morpho));
        (IVaultV2 vault, address adapter, bytes memory forceDeallocateData, address onBehalf, address caller) =
            abi.decode(data, (IVaultV2, address, bytes, address, address));

        vault.forceDeallocate(adapter, forceDeallocateData, assets, onBehalf);
        vault.withdraw(assets, address(this), onBehalf);

        address asset = vault.asset();
        uint256 balance = IERC20(asset).balanceOf(address(this));
        SafeERC20Lib.safeTransfer(asset, caller, balance - assets);
    }
}

contract MidnightAdapterGasTest is BaseTest {
    uint256 internal constant TICK = 4400;
    uint256 internal constant GAS_LIMIT = 10_000_000;

    // Copied from Midnight's ConstantsLib, which only compiles for Osaka.
    uint256 internal constant MAX_COLLATERALS = 128;
    uint32 internal constant MAX_CONTINUOUS_FEE = uint32(0.01e18 / uint256(365 days));
    uint256 internal constant MAX_SETTLEMENT_FEE_0_DAYS = 0.000014e18;
    uint256 internal constant MAX_SETTLEMENT_FEE_1_DAY = 0.000014e18;
    uint256 internal constant MAX_SETTLEMENT_FEE_7_DAYS = 0.000098e18;
    uint256 internal constant MAX_SETTLEMENT_FEE_30_DAYS = 0.000417e18;
    uint256 internal constant MAX_SETTLEMENT_FEE_90_DAYS = 0.00125e18;
    uint256 internal constant MAX_SETTLEMENT_FEE_180_DAYS = 0.0025e18;
    uint256 internal constant MAX_SETTLEMENT_FEE_360_DAYS = 0.005e18;

    address internal borrower = makeAddr("borrower");
    address internal badDebtLender = makeAddr("bad-debt-lender");
    address internal forceCaller = makeAddr("force-caller");

    IMidnight internal midnight;
    IMidnightAdapter internal adapter;
    IMidnightAdapterPriceRatifierV1 internal priceSubRatifier;
    ISetterRatifier internal setterRatifier;
    ERC20Mock internal collateralToken;
    CollateralParams internal collateralParams;
    WorstCaseForceDeallocator internal deallocator;
    FlashLoanForceDeallocator internal exiter;
    IMorpho internal morpho;
    address internal depositor;
    address internal performanceFeeRecipient;
    address internal managementFeeRecipient;
    address internal onBehalf;
    bytes32 internal soldMarketId;
    bytes internal forceDeallocateData;
    uint256 internal oneToken;
    uint256 internal initialAssets;
    uint256 internal soldCollateralIndex;
    uint256 internal soldUnits;
    uint256 internal claimableSettlementFeeBefore;
    uint256 internal continuousFeeCreditBefore;
    uint256 internal delegatedAllowance;
    uint256 internal onBehalfSharesBefore;

    function setUp() public override {
        vm.setEvmVersion("osaka");
        vm.pauseGasMetering();
        super.setUp();

        morpho = IMorpho(deployCode("Morpho.sol", abi.encode(makeAddr("morpho-owner"))));
        exiter = new FlashLoanForceDeallocator(morpho);
        deallocator = new WorstCaseForceDeallocator();

        oneToken = 10 ** underlyingTokenDecimals;
        initialAssets = 100_000_000 * oneToken;

        vm.startPrank(owner);
        midnight = IMidnight(deployCode("Midnight.sol:Midnight"));
        midnight.enableLltv(1e18);
        midnight.enableLiquidationCursor(0.25e18);
        midnight.setFeeSetter(address(this));
        vm.stopPrank();

        for (uint256 i; i < 7; i++) {
            midnight.setDefaultSettlementFee(address(underlyingToken), i, _maxSettlementFee(i));
        }
        midnight.setDefaultContinuousFee(address(underlyingToken), MAX_CONTINUOUS_FEE);

        collateralToken = new ERC20Mock(18);
        OracleMock oracle = new OracleMock();
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
        _submitAndSet(
            address(vault),
            abi.encodeCall(IVaultV2.setForceDeallocatePenalty, (address(adapter), MAX_FORCE_DEALLOCATE_PENALTY))
        );
        vm.prank(allocator);
        adapter.setIsSubRatifier(address(priceSubRatifier), true);

        _increaseCaps(abi.encode("this", address(adapter)));
        _increaseCaps(abi.encode("collateralToken", address(collateralToken)));
        _increaseCaps(abi.encode("collateralParams", collateralParams));
        _increaseCaps(abi.encode("enterGate", address(0)));
        _increaseCaps(abi.encode("liquidatorGate", address(0)));
        _increaseCaps(abi.encode("rcfThreshold", uint256(0)));
        _increaseCaps(abi.encode("this/duration", address(adapter), 7 days));

        vm.startPrank(address(this));
        SafeERC20Lib.safeApprove(address(underlyingToken), address(midnight), type(uint256).max);
        SafeERC20Lib.safeApprove(address(collateralToken), address(midnight), type(uint256).max);
        vm.stopPrank();

        uint256 maxMarkets = adapter.MAX_MARKETS();
        CollateralParams[] memory soldCollaterals = _soldCollaterals();
        soldCollateralIndex = _collateralIndex(soldCollaterals, address(collateralToken));
        for (uint256 i; i < soldCollaterals.length; i++) {
            if (soldCollaterals[i].token != address(collateralToken)) {
                _increaseCaps(abi.encode("collateralToken", soldCollaterals[i].token));
                _increaseCaps(abi.encode("collateralParams", soldCollaterals[i]));
            }
        }

        depositor = makeAddr("depositor");
        deal(address(underlyingToken), depositor, initialAssets);
        vm.startPrank(depositor);
        SafeERC20Lib.safeApprove(address(underlyingToken), address(vault), initialAssets);
        vault.deposit(initialAssets, depositor);
        vm.stopPrank();

        uint256[] memory purchasedUnits = new uint256[](maxMarkets);
        CollateralParams[] memory singleCollateral = new CollateralParams[](1);
        singleCollateral[0] = collateralParams;
        Market memory soldMarket;
        for (uint256 i; i < maxMarkets; i++) {
            Market memory market;
            if (i == 0) {
                soldMarket = _market(8 days, soldCollaterals);
                market = soldMarket;
            } else {
                market = _market(8 days + i * 1 minutes, singleCollateral);
            }
            purchasedUnits[i] = _buy(market, initialAssets / (2 * maxMarkets), i == 0 ? soldCollateralIndex : 0);
        }
        assertEq(adapter.marketIdsLength(), maxMarkets, "markets after buys");

        for (uint256 i; i < maxMarkets; i++) {
            Market memory market;
            uint256 collateralIndex;
            if (i == 0) {
                market = soldMarket;
                collateralIndex = soldCollateralIndex;
            } else {
                market = _market(8 days + i * 1 minutes, singleCollateral);
            }
            _createBadDebt(market, collateralIndex, purchasedUnits[i], i);
        }

        onBehalf = depositor;
        delegatedAllowance = type(uint128).max;
        vm.startPrank(depositor);
        vault.approve(address(exiter), delegatedAllowance);
        vault.transfer(address(exiter), 1);
        vm.stopPrank();
        onBehalfSharesBefore = vault.balanceOf(onBehalf);

        performanceFeeRecipient = makeAddr("performance-fee-recipient");
        managementFeeRecipient = makeAddr("management-fee-recipient");
        _submitAndSet(address(vault), abi.encodeCall(IVaultV2.setPerformanceFeeRecipient, (performanceFeeRecipient)));
        _submitAndSet(address(vault), abi.encodeCall(IVaultV2.setManagementFeeRecipient, (managementFeeRecipient)));
        _submitAndSet(address(vault), abi.encodeCall(IVaultV2.setPerformanceFee, (MAX_PERFORMANCE_FEE)));
        _submitAndSet(address(vault), abi.encodeCall(IVaultV2.setManagementFee, (MAX_MANAGEMENT_FEE)));
        vm.prank(allocator);
        vault.setMaxRate(MAX_MAX_RATE);

        vm.warp(block.timestamp + 6 hours);

        soldMarketId = adapter.marketIds(0);
        soldMarket = midnight.toMarket(soldMarketId);
        _assertCollateralSetup(soldMarket.collateralParams);
        _assertMarketSetup(soldMarketId, maxMarkets);

        (uint128 currentCredit, uint128 pendingFee,) =
            midnight.updatePositionView(soldMarket, soldMarketId, address(adapter));
        assertGt(uint256(currentCredit) - pendingFee, 0, "sold market credit");
        soldUnits = currentCredit;
        assertGt(soldUnits, 0, "sold units");
        deal(address(underlyingToken), address(morpho), soldUnits);

        // The exiter takes the credit and pays the settlement fee out of its own balance.
        deal(address(underlyingToken), address(exiter), soldUnits);
        vm.prank(address(exiter));
        midnight.setIsAuthorized(address(adapter), true, address(exiter));

        claimableSettlementFeeBefore = midnight.claimableSettlementFee(address(underlyingToken));
        continuousFeeCreditBefore = midnight.continuousFeeCredit(soldMarketId);
        forceDeallocateData = abi.encode(soldMarket, address(exiter));

        assertEq(vault.forceDeallocatePenalty(address(adapter)), MAX_FORCE_DEALLOCATE_PENALTY);
        assertNotEq(performanceFeeRecipient, managementFeeRecipient, "fee recipients");
        assertEq(vault.balanceOf(performanceFeeRecipient), 0, "performance fee shares before");
        assertEq(vault.balanceOf(managementFeeRecipient), 0, "management fee shares before");
        assertEq(onBehalf, depositor, "delegated on behalf");
        assertNotEq(forceCaller, onBehalf, "caller");
        assertNotEq(address(exiter), onBehalf, "exiter");
        assertGt(onBehalfSharesBefore, 0, "onBehalf shares");
        assertEq(vault.allowance(onBehalf, address(exiter)), delegatedAllowance, "delegated allowance");
        assertEq(underlyingToken.balanceOf(address(morpho)), soldUnits, "Morpho Blue flash loan balance");
        vm.resumeGasMetering();
    }

    /// @dev Exercises the worst-case force deallocation through a Morpho Blue flash loan.
    /// forge-config: default.isolate = true
    function testForceDeallocateGasWorstCase() public {
        bytes memory callData = abi.encodeCall(
            FlashLoanForceDeallocator.forceDeallocate,
            (vault, address(adapter), forceDeallocateData, soldUnits, onBehalf)
        );
        deallocator.forceDeallocate(
            exiter,
            vault,
            address(adapter),
            forceDeallocateData,
            soldUnits,
            onBehalf,
            forceCaller,
            GAS_LIMIT - _intrinsicGas(callData)
        );

        uint256 sharesSpent = onBehalfSharesBefore - vault.balanceOf(onBehalf);
        assertGt(sharesSpent, vault.previewWithdraw(soldUnits), "penalty shares");
        assertGt(vault.balanceOf(performanceFeeRecipient), 0, "performance fee shares");
        assertGt(vault.balanceOf(managementFeeRecipient), 0, "management fee shares");
        assertGt(
            midnight.claimableSettlementFee(address(underlyingToken)), claimableSettlementFeeBefore, "settlement fee"
        );
        assertGt(midnight.continuousFeeCredit(soldMarketId), continuousFeeCreditBefore, "continuous fee");
        assertEq(adapter.marketIdsLength(), adapter.MAX_MARKETS() - 1, "sold market removed");
        assertEq(vault.allowance(onBehalf, address(exiter)), delegatedAllowance - sharesSpent, "allowance spent");
        assertEq(underlyingToken.balanceOf(address(morpho)), soldUnits, "Morpho Blue repaid");
        assertEq(underlyingToken.balanceOf(address(exiter)), 0, "exiter balance");
        assertGt(midnight.credit(soldMarketId, address(exiter)), 0, "exiter credit");
        assertGt(underlyingToken.balanceOf(forceCaller), 0, "force caller received assets");
    }

    /// @dev Returns the intrinsic gas for a transaction with the given calldata. The EIP-7623 calldata floor doesn't reduce the gas available to execution.
    function _intrinsicGas(bytes memory callData) internal pure returns (uint256 gas) {
        gas = 21_000;
        for (uint256 i = 0; i < callData.length; i++) {
            gas += callData[i] == 0 ? 4 : 16;
        }
    }

    function _createBadDebt(Market memory market, uint256 collateralIndex, uint256 boughtUnits, uint256 index)
        internal
    {
        uint256 debtUnits = boughtUnits / 10_000;
        if (debtUnits < 2) debtUnits = 2;

        address badBorrower = makeAddr(string.concat("bad-borrower-", vm.toString(index)));
        Offer memory offer = Offer({
            market: market,
            buy: false,
            maker: badBorrower,
            start: block.timestamp,
            expiry: market.maturity,
            tick: MAX_TICK,
            group: bytes32(0),
            callback: address(0),
            callbackData: "",
            receiverIfMakerIsSeller: badBorrower,
            ratifier: address(setterRatifier),
            reduceOnly: false,
            maxUnits: uint128(debtUnits),
            maxAssets: 0,
            continuousFeeCap: type(uint256).max
        });
        bytes32 root = HashLib.hashOffer(offer);

        uint256 oraclePrice = OracleMock(market.collateralParams[collateralIndex].oracle).price();
        uint256 collateralAmount = debtUnits * 135 * 1e18 / (100 * oneToken);
        if (collateralAmount == 0) collateralAmount = 1;

        vm.startPrank(badBorrower);
        midnight.setIsAuthorized(address(setterRatifier), true, badBorrower);
        midnight.setIsAuthorized(address(this), true, badBorrower);
        vm.stopPrank();

        address collateralTokenAddress = market.collateralParams[collateralIndex].token;
        deal(collateralTokenAddress, address(this), collateralAmount);
        midnight.supplyCollateral(market, collateralIndex, collateralAmount, badBorrower);

        vm.prank(badBorrower);
        setterRatifier.setIsRootRatified(badBorrower, root, true);
        deal(address(underlyingToken), badDebtLender, 2 * debtUnits);
        vm.startPrank(badDebtLender);
        SafeERC20Lib.safeApprove(address(underlyingToken), address(midnight), 0);
        SafeERC20Lib.safeApprove(address(underlyingToken), address(midnight), type(uint256).max);
        midnight.take(
            offer, abi.encode(root, uint256(0), new bytes32[](0)), debtUnits, badDebtLender, address(0), address(0), ""
        );
        vm.stopPrank();

        OracleMock marketOracle = OracleMock(market.collateralParams[collateralIndex].oracle);
        marketOracle.setPrice(oraclePrice / 4);
        bytes32 marketId = adapter.marketIds(index);
        uint128 lossFactorBefore = midnight.lossFactor(marketId);
        midnight.liquidate(market, collateralIndex, 0, 0, badBorrower, false, address(this), address(0), "");
        assertNotEq(midnight.lossFactor(marketId), lossFactorBefore, "loss factor");

        uint256 remainingDebt = midnight.debt(marketId, badBorrower);
        assertGt(remainingDebt, 0, "remaining debt");
        deal(address(underlyingToken), address(this), remainingDebt);
        midnight.repay(market, remainingDebt, badBorrower, address(0), "");
        assertEq(midnight.debt(marketId, badBorrower), 0, "debt repaid");
        marketOracle.setPrice(oraclePrice);
    }

    function _assertCollateralSetup(CollateralParams[] memory collaterals) internal view {
        assertEq(collaterals.length, MAX_COLLATERALS, "collateral count");
        for (uint256 i = 1; i < collaterals.length; i++) {
            assertLt(uint160(collaterals[i - 1].token), uint160(collaterals[i].token), "collateral sort");
        }
        for (uint256 i; i < collaterals.length; i++) {
            bytes32 tokenId = keccak256(abi.encode("collateralToken", collaterals[i].token));
            bytes32 paramsId = keccak256(abi.encode("collateralParams", collaterals[i]));
            assertEq(vault.absoluteCap(tokenId), type(uint128).max, "absolute token cap");
            assertEq(vault.relativeCap(tokenId), WAD, "relative token cap");
            assertEq(vault.absoluteCap(paramsId), type(uint128).max, "absolute collateral cap");
            assertEq(vault.relativeCap(paramsId), WAD, "relative collateral cap");
        }
    }

    function _assertMarketSetup(bytes32 soldId, uint256 maxMarkets) internal view {
        uint16[7] memory settlementFeeCbps = midnight.settlementFeeCbps(soldId);
        for (uint256 i; i < 7; i++) {
            assertEq(settlementFeeCbps[i], uint16(_maxSettlementFee(i) / 1e12), "settlement fee setting");
        }
        assertEq(midnight.continuousFee(soldId), MAX_CONTINUOUS_FEE, "continuous fee setting");

        for (uint256 i; i < maxMarkets; i++) {
            bytes32 marketId = adapter.marketIds(i);
            Market memory market = midnight.toMarket(marketId);
            MarketData memory marketData = adapter.marketData(marketId);
            assertNotEq(midnight.lossFactor(marketId), marketData.lossFactor, "bad debt loss factor");
            (uint128 currentCredit, uint128 pendingFee,) =
                midnight.updatePositionView(market, marketId, address(adapter));
            assertGt(uint256(currentCredit) - pendingFee, 0, "market credit");
        }
    }

    function _soldCollaterals() internal returns (CollateralParams[] memory collaterals) {
        collaterals = new CollateralParams[](MAX_COLLATERALS);
        collaterals[0] = collateralParams;
        for (uint256 i = 1; i < collaterals.length; i++) {
            collaterals[i] = CollateralParams(
                address(new ERC20Mock(18)),
                collateralParams.lltv,
                collateralParams.liquidationCursor,
                collateralParams.oracle
            );
        }
        for (uint256 i; i < collaterals.length; i++) {
            for (uint256 j = i + 1; j < collaterals.length; j++) {
                if (uint160(collaterals[j].token) < uint160(collaterals[i].token)) {
                    CollateralParams memory collateral = collaterals[i];
                    collaterals[i] = collaterals[j];
                    collaterals[j] = collateral;
                }
            }
        }
    }

    function _collateralIndex(CollateralParams[] memory collaterals, address token)
        internal
        pure
        returns (uint256 index)
    {
        while (collaterals[index].token != token) index++;
    }

    function _buy(Market memory market, uint256 assets, uint256 collateralIndex) internal returns (uint256 units) {
        units = assets * WAD / TickLib.tickToPrice(TICK);
        Offer memory offer = Offer({
            market: market,
            buy: true,
            maker: address(adapter),
            start: block.timestamp,
            expiry: market.maturity,
            tick: TICK,
            group: keccak256(abi.encode("buy", market.maturity)),
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
        priceSubRatifier.setIsRootRatified(address(adapter), root, true, allocator);
        bytes memory ratifierData =
            abi.encode(address(priceSubRatifier), abi.encode(root, uint256(0), new bytes32[](0), address(0)));

        uint256 collateral = units * 2e18 / oneToken;
        deal(address(collateralToken), borrower, collateral);
        vm.startPrank(borrower);
        collateralToken.approve(address(midnight), collateral);
        midnight.supplyCollateral(market, collateralIndex, collateral, borrower);
        midnight.take(offer, ratifierData, units, borrower, borrower, address(0), "");
        vm.stopPrank();
    }

    function _maxSettlementFee(uint256 index) internal pure returns (uint256) {
        return [
            MAX_SETTLEMENT_FEE_0_DAYS,
            MAX_SETTLEMENT_FEE_1_DAY,
            MAX_SETTLEMENT_FEE_7_DAYS,
            MAX_SETTLEMENT_FEE_30_DAYS,
            MAX_SETTLEMENT_FEE_90_DAYS,
            MAX_SETTLEMENT_FEE_180_DAYS,
            MAX_SETTLEMENT_FEE_360_DAYS
        ][index];
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
        _submitAndSet(address(vault), abi.encodeCall(IVaultV2.increaseRelativeCap, (idData, WAD)));
    }

    function _market(uint256 duration, CollateralParams[] memory collaterals)
        internal
        view
        returns (Market memory market)
    {
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
