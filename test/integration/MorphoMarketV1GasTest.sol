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
import {Vm} from "../../lib/forge-std/src/Vm.sol";

contract MorphoMarketV1IntegrationTest is BaseTest {
    using MarketParamsLib for MarketParams;
    IMorpho internal morpho;
    ERC20Mock internal collateralToken;
    OracleMock internal oracle;
    IrmMock internal irm;
    MarketParams[] internal marketParamsArray;


    IMorphoMarketV1AdapterFactory internal factory;
    address morphoOwner = makeAddr("MorphoOwner");

    uint MAX_N = 50;

    function setUp() public virtual override {
        super.setUp();

        /* MORPHO SETUP */

        morpho = IMorpho(deployCode("Morpho.sol", abi.encode(morphoOwner)));
        oracle = new OracleMock();
        irm = new IrmMock();

        oracle.setPrice(ORACLE_PRICE_SCALE);

        vm.startPrank(morphoOwner);
        morpho.enableIrm(address(irm));
        morpho.enableLltv(0.8 ether);
        vm.stopPrank();

        factory = new MorphoMarketV1AdapterFactory();

        vm.prank(allocator);
        vault.setMaxRate(MAX_MAX_RATE);

        deal(address(underlyingToken), address(vault), type(uint256).max);

        marketParamsArray = new MarketParams[](MAX_N);

        MarketParams memory marketParams;
        for (uint256 i = 0; i < MAX_N; i++) {
            marketParams = MarketParams({
                loanToken: address(underlyingToken),
                collateralToken: address(bytes20(keccak256(abi.encode("collateralToken", i)))),
                irm: address(irm),
                oracle: address(oracle),
                lltv: 0.8 ether
            });

            MorphoMarketV1Adapter(
                factory.createMorphoMarketV1Adapter(address(vault), address(morpho), marketParams)
            );
            // uint256 g = vm.lastCallGas().gasTotalUsed;
            // console.log("CREATION: %s", g);

            vm.prank(morphoOwner);
            morpho.createMarket(marketParams);
            marketParamsArray[i] = marketParams;
        }
    }

    function _setupMarket(uint256 i) internal {

        MarketParams memory marketParams;
            marketParams = marketParamsArray[i];
            IMorphoMarketV1Adapter adapter = MorphoMarketV1Adapter(
                factory.morphoMarketV1Adapter(address(vault), address(morpho), marketParams.id())
            );

            vm.prank(curator);
            vault.submit(abi.encodeCall(IVaultV2.addAdapter, (address(adapter))));
            vault.addAdapter(address(adapter));

            bytes memory collateralId = abi.encode("collateralToken", marketParams.collateralToken);
            bytes memory adapterId = abi.encode("this", address(adapter));

            increaseAbsoluteCap(collateralId, type(uint128).max);
            increaseRelativeCap(collateralId, WAD);
            increaseAbsoluteCap(adapterId, type(uint128).max);
            increaseRelativeCap(adapterId, WAD);

            vm.prank(allocator);
            vault.allocate(address(adapter), hex"", 1);
    }

    /// forge-config: default.isolate = true
    function testAll() public {
        for (uint256 i = 0; i < MAX_N; i++) {
            _setupMarket(i);
            vault.totalAssets();
            uint256 used = vm.lastCallGas().gasTotalUsed;
            console.log("%s: %s", i+1, used);
        }
    }
}
