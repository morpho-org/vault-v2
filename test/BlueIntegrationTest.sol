// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import "./BaseTest.sol";
import {MorphoBlueAdapter} from "../src/adapters/MorphoBlueAdapter.sol";
import {MorphoBlueAdapterFactory} from "../src/adapters/MorphoBlueAdapterFactory.sol";
import {ERC20Mock} from "./mocks/ERC20Mock.sol";
import {OracleMock} from "../lib/morpho-blue/src/mocks/OracleMock.sol";
import {VaultV2Mock} from "./mocks/VaultV2Mock.sol";
import {IrmMock} from "../lib/morpho-blue/src/mocks/IrmMock.sol";
import {IMorpho, MarketParams, Id, Market} from "../lib/morpho-blue/src/interfaces/IMorpho.sol";
import {MorphoBalancesLib} from "../lib/morpho-blue/src/libraries/periphery/MorphoBalancesLib.sol";
import {MarketParamsLib} from "../lib/morpho-blue/src/libraries/MarketParamsLib.sol";
import {IERC20} from "../src/interfaces/IERC20.sol";
import {IVaultV2} from "../src/interfaces/IVaultV2.sol";
import {IMorphoBlueAdapter} from "../src/adapters/interfaces/IMorphoBlueAdapter.sol";
import {IMorphoBlueAdapterFactory} from "../src/adapters/interfaces/IMorphoBlueAdapterFactory.sol";

contract BlueIntegrationTest is BaseTest {
    using MorphoBalancesLib for IMorpho;
    using MarketParamsLib for MarketParams;

    MorphoBlueAdapterFactory internal factory;
    MorphoBlueAdapter internal adapter;
    MarketParams internal marketParams1;
    MarketParams internal marketParams2;
    Id internal marketId1;
    Id internal marketId2;
    ERC20Mock internal collateralToken;
    ERC20Mock internal rewardToken;
    OracleMock internal oracle;
    IrmMock internal irm;
    IMorpho internal morpho;
    address internal recipient;
    bytes32[] internal expectedIds1;
    bytes32[] internal expectedIds2;
    bytes[] internal expectedIdData1;
    bytes[] internal expectedIdData2;

    uint256 internal constant MIN_TEST_ASSETS = 10;
    uint256 internal constant MAX_TEST_ASSETS = 1e24;

    function setUp() public override {
        super.setUp();

        /* MORPHO SETUP */

        address morphoOwner = makeAddr("MorphoOwner");
        morpho = IMorpho(deployCode("Morpho.sol", abi.encode(morphoOwner)));

        collateralToken = new ERC20Mock();
        rewardToken = new ERC20Mock();
        oracle = new OracleMock();
        irm = new IrmMock();

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

        factory = new MorphoBlueAdapterFactory(address(morpho));
        adapter = MorphoBlueAdapter(factory.createMorphoBlueAdapter(address(vault)));

        expectedIdData1 = new bytes[](3);
        expectedIdData1[0] = abi.encode("adapter", address(adapter));
        expectedIdData1[1] = abi.encode("collateralToken", marketParams1.collateralToken);
        expectedIdData1[2] = abi.encode(
            "collateralToken/oracle/lltv", marketParams1.collateralToken, marketParams1.oracle, marketParams1.lltv
        );

        expectedIdData2 = new bytes[](3);
        expectedIdData2[0] = abi.encode("adapter", address(adapter));
        expectedIdData2[1] = abi.encode("collateralToken", marketParams2.collateralToken);
        expectedIdData2[2] = abi.encode(
            "collateralToken/oracle/lltv", marketParams2.collateralToken, marketParams2.oracle, marketParams2.lltv
        );

        expectedIds1 = new bytes32[](3);
        expectedIds1[0] = keccak256(abi.encode("adapter", address(adapter)));
        expectedIds1[1] = keccak256(abi.encode("collateralToken", marketParams1.collateralToken));
        expectedIds1[2] = keccak256(
            abi.encode(
                "collateralToken/oracle/lltv", marketParams1.collateralToken, marketParams1.oracle, marketParams1.lltv
            )
        );

        expectedIds2 = new bytes32[](3);
        expectedIds2[0] = keccak256(abi.encode("adapter", address(adapter)));
        expectedIds2[1] = keccak256(abi.encode("collateralToken", marketParams2.collateralToken));
        expectedIds2[2] = keccak256(
            abi.encode(
                "collateralToken/oracle/lltv", marketParams2.collateralToken, marketParams2.oracle, marketParams2.lltv
            )
        );

        vm.prank(curator);
        vault.submit(abi.encodeCall(IVaultV2.setIsAdapter, (address(adapter), true)));
        vault.setIsAdapter(address(adapter), true);

        vm.startPrank(curator);
        vault.submit(abi.encodeCall(IVaultV2.increaseAbsoluteCap, (expectedIdData1[0], type(uint256).max)));
        vault.submit(abi.encodeCall(IVaultV2.increaseAbsoluteCap, (expectedIdData1[1], type(uint256).max)));
        vault.submit(abi.encodeCall(IVaultV2.increaseAbsoluteCap, (expectedIdData1[2], type(uint256).max)));
        vault.submit(abi.encodeCall(IVaultV2.increaseRelativeCap, (expectedIdData1[0], WAD)));
        vault.submit(abi.encodeCall(IVaultV2.increaseRelativeCap, (expectedIdData1[1], WAD)));
        vault.submit(abi.encodeCall(IVaultV2.increaseRelativeCap, (expectedIdData1[2], WAD)));
        vault.submit(abi.encodeCall(IVaultV2.increaseAbsoluteCap, (expectedIdData2[2], type(uint256).max)));
        vault.submit(abi.encodeCall(IVaultV2.increaseRelativeCap, (expectedIdData2[2], WAD)));
        vm.stopPrank();

        vault.increaseAbsoluteCap(expectedIdData1[0], type(uint256).max);
        vault.increaseAbsoluteCap(expectedIdData1[1], type(uint256).max);
        vault.increaseAbsoluteCap(expectedIdData1[2], type(uint256).max);
        vault.increaseRelativeCap(expectedIdData1[0], WAD);
        vault.increaseRelativeCap(expectedIdData1[1], WAD);
        vault.increaseRelativeCap(expectedIdData1[2], WAD);
        vault.increaseAbsoluteCap(expectedIdData2[2], type(uint256).max);
        vault.increaseRelativeCap(expectedIdData2[2], WAD);

        deal(address(underlyingToken), address(this), type(uint256).max);
        underlyingToken.approve(address(vault), type(uint256).max);
    }

    function testSetup() public {
        vault.deposit(100 ether, address(this));

        vm.prank(allocator);
        vault.allocate(address(adapter), abi.encode(marketParams1), 50 ether);
    }
}
