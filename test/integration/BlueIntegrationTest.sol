// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Morpho Association
pragma solidity ^0.8.0;

import "../BaseTest.sol";

import {MorphoBlueAdapter} from "../../src/adapters/MorphoBlueAdapter.sol";
import {MorphoBlueAdapterFactory} from "../../src/adapters/MorphoBlueAdapterFactory.sol";

import {ORACLE_PRICE_SCALE} from "../../lib/morpho-blue/src/libraries/ConstantsLib.sol";
import {OracleMock} from "../../lib/morpho-blue/src/mocks/OracleMock.sol";
import {IrmMock} from "../../lib/morpho-blue/src/mocks/IrmMock.sol";
import {IMorpho, MarketParams, Id} from "../../lib/morpho-blue/src/interfaces/IMorpho.sol";
import {MarketParamsLib} from "../../lib/morpho-blue/src/libraries/MarketParamsLib.sol";
import {MorphoBalancesLib} from "../../lib/morpho-blue/src/libraries/periphery/MorphoBalancesLib.sol";

contract BlueIntegrationTest is BaseTest {
    IMorpho internal morpho;
    ERC20Mock internal collateralToken;
    OracleMock internal oracle;
    IrmMock internal irm;
    MarketParams internal marketParams1;
    MarketParams internal marketParams2;

    MorphoBlueAdapterFactory internal factory;
    MorphoBlueAdapter internal adapter;

    bytes[] internal expectedIdData1;
    bytes[] internal expectedIdData2;

    uint256 internal constant MIN_TEST_ASSETS = 10;
    uint256 internal constant MAX_TEST_ASSETS = 1e24;

    function setUp() public virtual override {
        super.setUp();

        /* MORPHO SETUP */

        address morphoOwner = makeAddr("MorphoOwner");
        morpho = IMorpho(deployCode("Morpho.sol", abi.encode(morphoOwner)));

        collateralToken = new ERC20Mock();
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

        factory = new MorphoBlueAdapterFactory();
        adapter = MorphoBlueAdapter(factory.createMorphoBlueAdapter(address(vault), address(morpho), address(irm)));

        expectedIdData1 = new bytes[](4);
        expectedIdData1[0] = abi.encode("adapter", address(adapter));
        expectedIdData1[1] = abi.encode("collateralToken", marketParams1.collateralToken);
        expectedIdData1[2] = abi.encode(
            "collateralToken/oracle/lltv", marketParams1.collateralToken, marketParams1.oracle, marketParams1.lltv
        );
        expectedIdData1[3] = abi.encode(address(adapter), marketParams1);

        expectedIdData2 = new bytes[](4);
        expectedIdData2[0] = abi.encode("adapter", address(adapter));
        expectedIdData2[1] = abi.encode("collateralToken", marketParams2.collateralToken);
        expectedIdData2[2] = abi.encode(
            "collateralToken/oracle/lltv", marketParams2.collateralToken, marketParams2.oracle, marketParams2.lltv
        );
        expectedIdData2[3] = abi.encode(address(adapter), marketParams2);

        vm.prank(curator);
        vault.submit(abi.encodeCall(IVaultV2.setIsAdapter, (address(adapter), true)));
        vault.setIsAdapter(address(adapter), true);

        increaseAbsoluteAndRelativeCapToMax(expectedIdData1[0]);
        increaseAbsoluteAndRelativeCapToMax(expectedIdData1[1]);
        increaseAbsoluteAndRelativeCapToMax(expectedIdData1[2]);
        increaseAbsoluteAndRelativeCapToMax(expectedIdData1[3]);
        // expectedIdData2[0] and expectedIdData2[1] are the same as expectedIdData1[0] and expectedIdData1[1]
        increaseAbsoluteAndRelativeCapToMax(expectedIdData2[2]);
        increaseAbsoluteAndRelativeCapToMax(expectedIdData2[3]);

        deal(address(underlyingToken), address(this), type(uint256).max);
        underlyingToken.approve(address(vault), type(uint256).max);
    }

    function increaseAbsoluteAndRelativeCapToMax(bytes memory idData) internal {
        vm.startPrank(curator);
        vault.submit(abi.encodeCall(IVaultV2.increaseAbsoluteCap, (idData, type(uint128).max)));
        vault.submit(abi.encodeCall(IVaultV2.increaseRelativeCap, (idData, WAD)));
        vm.stopPrank();

        vault.increaseAbsoluteCap(idData, type(uint128).max);
        vault.increaseRelativeCap(idData, WAD);
    }
}
