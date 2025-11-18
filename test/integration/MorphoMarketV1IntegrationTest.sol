// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Morpho Association
pragma solidity ^0.8.0;

import "../BaseTest.sol";

import {MorphoMarketV1Adapter} from "../../src/adapters/MorphoMarketV1Adapter.sol";
import {MorphoMarketV1AdapterFactory} from "../../src/adapters/MorphoMarketV1AdapterFactory.sol";
import {IMorphoMarketV1AdapterFactory} from "../../src/adapters/interfaces/IMorphoMarketV1AdapterFactory.sol";
import {IMorphoMarketV1Adapter} from "../../src/adapters/interfaces/IMorphoMarketV1Adapter.sol";

import {ORACLE_PRICE_SCALE} from "../../lib/morpho-blue/src/libraries/ConstantsLib.sol";
import {OracleMock} from "../../lib/morpho-blue/src/mocks/OracleMock.sol";
import {IrmMock} from "../../lib/morpho-blue/src/mocks/IrmMock.sol";
import {IMorpho, MarketParams, Id} from "../../lib/morpho-blue/src/interfaces/IMorpho.sol";
import {MarketParamsLib} from "../../lib/morpho-blue/src/libraries/MarketParamsLib.sol";
import {MorphoBalancesLib} from "../../lib/morpho-blue/src/libraries/periphery/MorphoBalancesLib.sol";

contract MorphoMarketV1IntegrationTest is BaseTest {
    IMorpho internal morpho;
    ERC20Mock internal collateralToken;
    OracleMock internal oracle;
    IrmMock internal irm;
    MarketParams internal marketParams1;
    MarketParams internal marketParams2;

    IMorphoMarketV1AdapterFactory internal factory;
    IMorphoMarketV1Adapter internal adapter;

    bytes[] internal expectedIdData1;
    bytes[] internal expectedIdData2;

    uint256 internal constant MIN_TEST_ASSETS = 10;
    uint256 internal constant MAX_TEST_ASSETS = 1e24;

    function setUp() public virtual override {
        super.setUp();

        /* MORPHO SETUP */

        address morphoOwner = makeAddr("MorphoOwner");
        morpho = IMorpho(deployCode("Morpho.sol", abi.encode(morphoOwner)));

        collateralToken = new ERC20Mock(18);
        oracle = new OracleMock();
        irm = new IrmMock();

        oracle.setPrice(ORACLE_PRICE_SCALE);

        marketParams1 = MarketParams({
            loanToken: address(underlyingToken),
            collateralToken: address(collateralToken),
            irm: address(irm),
            oracle: address(oracle),
            lltv: 0.8 ether
        });

        marketParams2 = MarketParams({
            loanToken: address(underlyingToken),
            collateralToken: address(collateralToken),
            irm: address(irm),
            oracle: address(oracle),
            lltv: 0.9 ether
        });

        vm.startPrank(morphoOwner);
        morpho.enableIrm(address(irm));
        morpho.enableLltv(0.8 ether);
        morpho.enableLltv(0.9 ether);
        vm.stopPrank();

        morpho.createMarket(marketParams1);
        morpho.createMarket(marketParams2);

        /* VAULT SETUP */

        factory = new MorphoMarketV1AdapterFactory();
        adapter = MorphoMarketV1Adapter(factory.createMorphoMarketV1Adapter(address(vault), address(morpho)));

        expectedIdData1 = new bytes[](3);
        expectedIdData1[0] = abi.encode("this", address(adapter));
        expectedIdData1[1] = abi.encode("collateralToken", marketParams1.collateralToken);
        expectedIdData1[2] = abi.encode("this/marketParams", address(adapter), marketParams1);

        expectedIdData2 = new bytes[](3);
        expectedIdData2[0] = abi.encode("this", address(adapter));
        expectedIdData2[1] = abi.encode("collateralToken", marketParams2.collateralToken);
        expectedIdData2[2] = abi.encode("this/marketParams", address(adapter), marketParams2);

        vm.prank(curator);
        vault.submit(abi.encodeCall(IVaultV2.addAdapter, (address(adapter))));
        vault.addAdapter(address(adapter));

        vm.prank(allocator);
        vault.setMaxRate(MAX_MAX_RATE);

        increaseAbsoluteCap(expectedIdData1[0], type(uint128).max);
        increaseRelativeCap(expectedIdData1[0], WAD);

        increaseAbsoluteCap(expectedIdData1[1], type(uint128).max);
        increaseRelativeCap(expectedIdData1[1], WAD);

        increaseAbsoluteCap(expectedIdData1[2], type(uint128).max);
        increaseRelativeCap(expectedIdData1[2], WAD);

        // expectedIdData2[0] and expectedIdData2[1] are the same as expectedIdData1[0] and expectedIdData1[1]
        increaseAbsoluteCap(expectedIdData2[2], type(uint128).max);
        increaseRelativeCap(expectedIdData2[2], WAD);

        deal(address(underlyingToken), address(this), type(uint256).max);
        underlyingToken.approve(address(vault), type(uint256).max);
    }
}
