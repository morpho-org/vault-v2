// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Morpho Association
pragma solidity ^0.8.0;

import "../BaseTest.sol";

import {MorphoMarketV1Adapter} from "../../src/adapters/MorphoMarketV1Adapter.sol";
import {MorphoMarketV1AdapterFactory} from "../../src/adapters/MorphoMarketV1AdapterFactory.sol";
import {IMorphoMarketV1AdapterFactory} from "../../src/adapters/interfaces/IMorphoMarketV1AdapterFactory.sol";
import {IMorphoMarketV1Adapter} from "../../src/adapters/interfaces/IMorphoMarketV1Adapter.sol";

import {ORACLE_PRICE_SCALE} from "../../lib/morpho-blue-irm/lib/morpho-blue/src/libraries/ConstantsLib.sol";
import {OracleMock} from "../../lib/morpho-blue-irm/lib/morpho-blue/src/mocks/OracleMock.sol";
import {IrmMock} from "../../lib/morpho-blue-irm/lib/morpho-blue/src/mocks/IrmMock.sol";
import {IMorpho, MarketParams, Id} from "../../lib/morpho-blue-irm/lib/morpho-blue/src/interfaces/IMorpho.sol";
import {MarketParamsLib} from "../../lib/morpho-blue-irm/lib/morpho-blue/src/libraries/MarketParamsLib.sol";
import {
    MorphoBalancesLib
} from "../../lib/morpho-blue-irm/lib/morpho-blue/src/libraries/periphery/MorphoBalancesLib.sol";
import {IAdaptiveCurveIrm} from "../../lib/morpho-blue-irm/src/adaptive-curve-irm/interfaces/IAdaptiveCurveIrm.sol";

contract MorphoMarketV1IntegrationTest is BaseTest {
    IMorpho internal morpho;
    ERC20Mock internal collateralToken;
    OracleMock internal oracle;
    IAdaptiveCurveIrm internal irm;
    MarketParams internal marketParams1;
    MarketParams internal marketParams2;

    IMorphoMarketV1AdapterFactory internal factory;
    IMorphoMarketV1Adapter internal adapter;

    bytes[] internal expectedIdData1;
    bytes[] internal expectedIdData2;

    uint256 internal constant MIN_TEST_ASSETS = 10;
    uint256 internal constant MAX_TEST_ASSETS = 1e24;

    uint MAX_N = 50;
    MarketParams[] internal marketParamsArray;

    function setUp() public virtual override {
        super.setUp();

        marketParamsArray = new MarketParams[](MAX_N);

        /* MORPHO SETUP */

        address morphoOwner = makeAddr("MorphoOwner");
        morpho = IMorpho(deployCode("Morpho.sol", abi.encode(morphoOwner)));

        irm = IAdaptiveCurveIrm(deployCode("AdaptiveCurveIrm.sol", abi.encode(address(morpho))));

        collateralToken = new ERC20Mock(18);
        oracle = new OracleMock();

        oracle.setPrice(ORACLE_PRICE_SCALE);

        vm.startPrank(morphoOwner);
        morpho.enableIrm(address(irm));
        morpho.enableLltv(0.8 ether);
        vm.stopPrank();

        factory = new MorphoMarketV1AdapterFactory(address(irm));
        adapter = MorphoMarketV1Adapter(factory.createMorphoMarketV1Adapter(address(vault), address(morpho)));

        vm.prank(curator);
        vault.submit(abi.encodeCall(IVaultV2.addAdapter, (address(adapter))));
        vault.addAdapter(address(adapter));

        vm.prank(allocator);
        vault.setMaxRate(MAX_MAX_RATE);

        deal(address(underlyingToken), address(vault), type(uint256).max);
        // underlyingToken.approve(address(vault), type(uint256).max);

        bytes memory thisId = abi.encode("this", address(adapter));
        increaseAbsoluteCap(thisId, type(uint128).max);
        increaseRelativeCap(thisId, WAD);

        MarketParams memory marketParams;
        for (uint256 i = 0; i < MAX_N; i++) {
            marketParams = MarketParams({
                loanToken: address(underlyingToken),
                collateralToken: address (new ERC20Mock(18)),
                irm: address(irm),
                oracle: address(oracle),
                lltv: 0.8 ether
            });

            marketParamsArray[i] = marketParams;

            vm.prank(morphoOwner);
            morpho.createMarket(marketParams);
        }
    }

  function _setupMarket(uint256 i) internal {
        MarketParams memory marketParams = marketParamsArray[i];

        bytes memory collateralId = abi.encode("collateralToken", marketParams.collateralToken);
        bytes memory marketParamsId = abi.encode("this/marketParams", address(adapter), marketParams);

        increaseAbsoluteCap(collateralId, type(uint128).max);
        increaseRelativeCap(collateralId, WAD);
        increaseAbsoluteCap(marketParamsId, type(uint128).max);
        increaseRelativeCap(marketParamsId, WAD);

        vm.prank(allocator);
        vault.allocate(address(adapter), abi.encode(marketParams), 1);
    }

    // function testAssets() public {
    //     uint assets = vault.totalAssets();
    //     uint used = vm.lastCallGas().gasTotalUsed;
    //     console.log("assets", assets);
    //     console.log("GAS   ", used);
    // }

    /// forge-config: default.isolate = true
    function testAll() public {
        for (uint256 i = 0; i < MAX_N; i++) {
            _setupMarket(i);
            vault.totalAssets();
            uint used = vm.lastCallGas().gasTotalUsed;
            console.log("%s: %s", i+1, used);
        }
    }
}
