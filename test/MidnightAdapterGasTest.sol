// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Morpho Association
pragma solidity ^0.8.0;

import {BaseTest} from "./BaseTest.sol";
import {IMidnightAdapter, IMidnightAdapterBase} from "../src/adapters/interfaces/IMidnightAdapter.sol";
import {IMidnightAdapterFactory} from "../src/adapters/interfaces/IMidnightAdapterFactory.sol";
import {
    IMidnightAdapterPriceRatifierV1
} from "../src/adapters/ratifiers/interfaces/IMidnightAdapterPriceRatifierV1.sol";
import {IVaultV2} from "../src/interfaces/IVaultV2.sol";
import {SafeERC20Lib} from "../src/libraries/SafeERC20Lib.sol";
import {WAD} from "../src/libraries/ConstantsLib.sol";
import {ERC20Mock} from "./mocks/ERC20Mock.sol";
import {OracleMock} from "../lib/morpho-blue/src/mocks/OracleMock.sol";
import {IMidnight, Market, Offer, CollateralParams} from "../lib/midnight/src/interfaces/IMidnight.sol";
import {HashLib} from "../lib/midnight/src/ratifiers/libraries/HashLib.sol";
import {ISetterRatifier} from "../lib/midnight/src/ratifiers/interfaces/ISetterRatifier.sol";
import {TickLib} from "../lib/midnight/src/libraries/TickLib.sol";
import {ORACLE_PRICE_SCALE} from "../lib/morpho-blue/src/libraries/ConstantsLib.sol";

/// @dev Calls forceDeallocate from a contract to meter only that call.
contract ForceDeallocator {
    function setUp(IVaultV2 vault, address adapter, uint256 assets) external {
        SafeERC20Lib.safeApprove(vault.asset(), address(vault), assets);
        vault.deposit(assets, address(this));
        SafeERC20Lib.safeApprove(vault.asset(), adapter, type(uint256).max);
    }

    function forceDeallocate(IVaultV2 vault, address adapter, bytes memory data, uint256 assets, uint256 gas) external {
        uint256 penaltyShares = vault.forceDeallocate{gas: gas}(adapter, data, assets, address(this));
        require(penaltyShares > 0, "no penalty");
    }
}

contract MidnightAdapterGasTest is BaseTest {
    /// @dev Price of about 0.994 assets per unit.
    uint256 internal constant TICK = 4400;
    uint256 internal constant HYPEREVM_SMALL_BLOCK_GAS_LIMIT = 3_000_000;

    address internal borrower = makeAddr("borrower");
    address internal lender = makeAddr("lender");

    IMidnight internal midnight;
    IMidnightAdapter internal adapter;
    IMidnightAdapterPriceRatifierV1 internal priceSubRatifier;
    ISetterRatifier internal setterRatifier;
    ERC20Mock internal collateralToken;
    CollateralParams internal collateralParams;
    uint256 internal oneToken;
    uint256 internal initialAssets;

    function setUp() public override {
        vm.setEvmVersion("osaka");
        super.setUp();

        oneToken = 10 ** underlyingTokenDecimals;
        initialAssets = 100_000 * oneToken;

        vm.startPrank(owner);
        midnight = IMidnight(deployCode("Midnight.sol:Midnight"));
        midnight.enableLltv(1e18);
        midnight.enableLiquidationCursor(0.25e18);
        vm.stopPrank();

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
        _submitAndSet(address(vault), abi.encodeCall(IVaultV2.setForceDeallocatePenalty, (address(adapter), 0.02e18)));
        vm.prank(allocator);
        adapter.setIsSubRatifier(address(priceSubRatifier), true);

        _increaseCaps(abi.encode("this", address(adapter)));
        _increaseCaps(abi.encode("collateralToken", address(collateralToken)));
        _increaseCaps(abi.encode("collateralParams", collateralParams));
        _increaseCaps(abi.encode("enterGate", address(0)));
        _increaseCaps(abi.encode("liquidatorGate", address(0)));
        _increaseCaps(abi.encode("rcfThreshold", uint256(0)));
        _increaseCaps(abi.encode("this/duration", address(adapter), 7 days));

        address depositor = makeAddr("depositor");
        deal(address(underlyingToken), depositor, initialAssets);
        vm.startPrank(depositor);
        SafeERC20Lib.safeApprove(address(underlyingToken), address(vault), initialAssets);
        vault.deposit(initialAssets, depositor);
        vm.stopPrank();
    }

    /// @dev Isolated so that every call is a separate transaction, with cold storage and fresh SSTORE pricing.
    /// forge-config: default.isolate = true
    function testForceDeallocateGasWithMaxMarkets() public {
        uint256 maxMarkets = adapter.MAX_MARKETS();
        Market memory market = _market(8 days);
        uint256 units = _buy(market, initialAssets / (2 * maxMarkets)) / 2;
        for (uint256 i = 1; i < maxMarkets; i++) {
            _buy(_market(8 days + i * 1 minutes), initialAssets / (2 * maxMarkets));
        }
        assertEq(adapter.marketIdsLength(), maxMarkets, "markets");

        Offer memory offer = Offer({
            market: market,
            buy: true,
            maker: lender,
            start: block.timestamp,
            expiry: market.maturity,
            tick: TICK,
            group: keccak256("force deallocation"),
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
        deal(address(underlyingToken), lender, units);
        vm.startPrank(lender);
        SafeERC20Lib.safeApprove(address(underlyingToken), address(midnight), units);
        midnight.setIsAuthorized(address(setterRatifier), true, lender);
        setterRatifier.setIsRootRatified(lender, root, true);
        vm.stopPrank();

        ForceDeallocator deallocator = new ForceDeallocator();
        deal(address(underlyingToken), address(deallocator), 2 * units);
        deallocator.setUp(vault, address(adapter), units);

        // So that the penalty withdrawal accrues interest.
        vm.warp(block.timestamp + 1 hours);
        bytes memory data = abi.encode(offer, abi.encode(root, uint256(0), new bytes32[](0)));
        // HyperEVM runs Cancun. The setup needs Osaka for clz, but the force deallocation doesn't execute it.
        vm.setEvmVersion("cancun");
        // The vault is the transaction's target, so the call gets the transaction's gas limit minus the intrinsic gas.
        deallocator.forceDeallocate(
            vault,
            address(adapter),
            data,
            units,
            HYPEREVM_SMALL_BLOCK_GAS_LIMIT
                - _intrinsicGas(
                    abi.encodeCall(IVaultV2.forceDeallocate, (address(adapter), data, units, address(deallocator)))
                )
        );
    }

    /// @dev Returns the intrinsic gas for a transaction with the given calldata, using Cancun pricing.
    function _intrinsicGas(bytes memory callData) internal pure returns (uint256 gas) {
        gas = 21_000;
        for (uint256 i = 0; i < callData.length; i++) {
            gas += callData[i] == 0 ? 4 : 16;
        }
    }

    /// @dev Has the borrower take a vault buy offer, and returns the bought units.
    function _buy(Market memory market, uint256 assets) internal returns (uint256 units) {
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
        midnight.supplyCollateral(market, 0, collateral, borrower);
        midnight.take(offer, ratifierData, units, borrower, borrower, address(0), "");
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
