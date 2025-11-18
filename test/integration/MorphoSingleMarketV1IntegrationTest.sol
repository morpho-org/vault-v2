// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Morpho Association
pragma solidity ^0.8.0;

import "../BaseTest.sol";

import {MorphoSingleMarketV1Adapter} from "../../src/adapters/MorphoSingleMarketV1Adapter.sol";
import {MorphoSingleMarketV1AdapterFactory} from "../../src/adapters/MorphoSingleMarketV1AdapterFactory.sol";
import {
    IMorphoSingleMarketV1AdapterFactory
} from "../../src/adapters/interfaces/IMorphoSingleMarketV1AdapterFactory.sol";
import {IMorphoSingleMarketV1Adapter} from "../../src/adapters/interfaces/IMorphoSingleMarketV1Adapter.sol";

import {ORACLE_PRICE_SCALE} from "../../lib/morpho-blue/src/libraries/ConstantsLib.sol";
import {OracleMock} from "../../lib/morpho-blue/src/mocks/OracleMock.sol";
import {IrmMock} from "../../lib/morpho-blue/src/mocks/IrmMock.sol";
import {IMorpho, MarketParams, Id} from "../../lib/morpho-blue/src/interfaces/IMorpho.sol";
import {MarketParamsLib} from "../../lib/morpho-blue/src/libraries/MarketParamsLib.sol";
import {MorphoBalancesLib} from "../../lib/morpho-blue/src/libraries/periphery/MorphoBalancesLib.sol";

contract MorphoSingleMarketV1IntegrationTest is BaseTest {
    IMorpho internal morpho;
    ERC20Mock internal collateralToken;
    OracleMock internal oracle;
    IrmMock internal irm;
    MarketParams internal marketParams;

    IMorphoSingleMarketV1AdapterFactory internal factory;
    IMorphoSingleMarketV1Adapter internal adapter;

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

        marketParams = MarketParams({
            loanToken: address(underlyingToken),
            collateralToken: address(collateralToken),
            irm: address(irm),
            oracle: address(oracle),
            lltv: 0.8 ether
        });

        vm.startPrank(morphoOwner);
        morpho.enableIrm(address(irm));
        morpho.enableLltv(0.8 ether);
        morpho.enableLltv(0.9 ether);
        vm.stopPrank();

        morpho.createMarket(marketParams);

        /* VAULT SETUP */

        factory = new MorphoSingleMarketV1AdapterFactory();
        adapter = MorphoSingleMarketV1Adapter(
            factory.createMorphoSingleMarketV1Adapter(address(vault), address(morpho), marketParams)
        );

        expectedIdData = new bytes[](3);
        expectedIdData[0] = abi.encode("morphoMarketV1", address(morpho));
        expectedIdData[1] = abi.encode("this", address(adapter));
        expectedIdData[2] = abi.encode("collateralToken", marketParams.collateralToken);

        vm.prank(curator);
        vault.submit(abi.encodeCall(IVaultV2.addAdapter, (address(adapter))));
        vault.addAdapter(address(adapter));

        vm.prank(allocator);
        vault.setMaxRate(MAX_MAX_RATE);

        increaseAbsoluteCap(expectedIdData[0], type(uint128).max);
        increaseRelativeCap(expectedIdData[0], WAD);

        increaseAbsoluteCap(expectedIdData[1], type(uint128).max);
        increaseRelativeCap(expectedIdData[1], WAD);

        increaseAbsoluteCap(expectedIdData[2], type(uint128).max);
        increaseRelativeCap(expectedIdData[2], WAD);

        deal(address(underlyingToken), address(this), type(uint256).max);
        underlyingToken.approve(address(vault), type(uint256).max);
    }
}
