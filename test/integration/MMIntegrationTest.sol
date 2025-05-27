// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import "../BaseTest.sol";

import {
    OracleMock,
    IrmMock,
    IMorpho,
    IMetaMorpho,
    ORACLE_PRICE_SCALE,
    MarketParams,
    MarketParamsLib,
    Id,
    MorphoBalancesLib
} from "../../lib/metamorpho/test/forge/helpers/IntegrationTest.sol";

import {IVaultV2Factory} from "../../src/interfaces/IVaultV2Factory.sol";
import {IVaultV2} from "../../src/interfaces/IVaultV2.sol";
import {IManualVicFactory} from "../../src/vic/interfaces/IManualVicFactory.sol";

import {VaultV2Factory} from "../../src/VaultV2Factory.sol";
import {ManualVic, ManualVicFactory} from "../../src/vic/ManualVicFactory.sol";
import "../../src/VaultV2.sol";
import {MetaMorphoAdapter} from "../../src/adapters/MetaMorphoAdapter.sol";
import {MetaMorphoAdapterFactory} from "../../src/adapters/MetaMorphoAdapterFactory.sol";

contract MMIntegrationTest is BaseTest {
    using MarketParamsLib for MarketParams;

    uint256 internal constant MAX_TEST_ASSETS = 1e32;

    // Morpho.
    address internal immutable morphoOwner = makeAddr("MorphoOwner");
    IMorpho internal morpho;
    ERC20Mock internal collateralToken;
    OracleMock internal oracle;
    IrmMock internal irm;

    // MetaMorpho factory.
    address metaMorphoFactory;

    // MetaMorpho.
    IMetaMorpho internal metaMorpho;
    address internal immutable mmOwner = makeAddr("mmOwner");
    address internal immutable mmAllocator = makeAddr("mmAllocator");
    address internal immutable mmCurator = makeAddr("mmCurator");
    uint256 internal constant MM_NB_MARKETS = 5;
    uint256 internal constant CAP = 1e18;
    uint256 internal constant MM_TIMELOCK = 1 weeks;
    MarketParams[] internal allMarketParams;
    MarketParams internal idleParams;

    // Adapter.
    MetaMorphoAdapterFactory internal metaMorphoAdapterFactory;
    MetaMorphoAdapter internal metaMorphoAdapter;

    function setUp() public virtual override {
        super.setUp();

        // Setup morpho.
        morpho = IMorpho(deployCode("Morpho.sol", abi.encode(morphoOwner)));
        collateralToken = new ERC20Mock();
        oracle = new OracleMock();
        irm = new IrmMock();

        metaMorphoFactory = address(new MockMetaMorphoFactory(address(morpho)));

        oracle.setPrice(ORACLE_PRICE_SCALE);

        irm.setApr(0.5 ether); // 50%.

        idleParams = MarketParams({
            loanToken: address(underlyingToken),
            collateralToken: address(0),
            oracle: address(0),
            irm: address(irm),
            lltv: 0
        });

        vm.startPrank(morphoOwner);
        morpho.enableIrm(address(irm));
        morpho.enableLltv(0);
        vm.stopPrank();

        morpho.createMarket(idleParams);

        for (uint256 i; i < MM_NB_MARKETS; ++i) {
            uint256 lltv = 0.8 ether / (i + 1);

            MarketParams memory marketParams = MarketParams({
                loanToken: address(underlyingToken),
                collateralToken: address(collateralToken),
                oracle: address(oracle),
                irm: address(irm),
                lltv: lltv
            });

            vm.prank(morphoOwner);
            morpho.enableLltv(lltv);

            morpho.createMarket(marketParams);

            allMarketParams.push(marketParams);
        }

        allMarketParams.push(idleParams);

        // Setup metaMorpho.
        metaMorpho = IMetaMorpho(
            deployCode(
                "MetaMorpho.sol",
                abi.encode(mmOwner, address(morpho), MM_TIMELOCK, address(underlyingToken), "metamorpho", "MM")
            )
        );
        vm.startPrank(mmOwner);
        metaMorpho.setCurator(mmCurator);
        metaMorpho.setIsAllocator(mmAllocator, true);
        vm.stopPrank();

        // Setup metaMorphoAdapter and vault.
        metaMorphoAdapterFactory = new MetaMorphoAdapterFactory(metaMorphoFactory);
        metaMorphoAdapter =
            MetaMorphoAdapter(metaMorphoAdapterFactory.createMetaMorphoAdapter(address(vault), address(metaMorpho)));

        vm.prank(curator);
        vault.submit(abi.encodeCall(IVaultV2.setIsAdapterFactory, (address(metaMorphoAdapterFactory), true)));
        vault.setIsAdapterFactory(address(metaMorphoAdapterFactory), true);

        bytes memory idData = abi.encode("adapter", address(metaMorphoAdapter));
        vm.startPrank(curator);
        vault.submit(abi.encodeCall(IVaultV2.setIsAdapter, (address(metaMorphoAdapter), true)));
        vault.submit(abi.encodeCall(IVaultV2.increaseAbsoluteCap, (idData, type(uint256).max)));
        vault.submit(abi.encodeCall(IVaultV2.increaseRelativeCap, (idData, 1e18)));
        vm.stopPrank();

        vault.setIsAdapter(address(metaMorphoAdapter), true);
        vault.increaseAbsoluteCap(idData, type(uint256).max);
        vault.increaseRelativeCap(idData, 1e18);

        // Approval.
        deal(address(underlyingToken), address(this), type(uint256).max);
        underlyingToken.approve(address(vault), type(uint256).max);
    }

    function setSupplyQueueIdle() public {
        setMetaMorphoCap(idleParams, type(uint184).max);
        Id[] memory supplyQueue = new Id[](1);
        supplyQueue[0] = idleParams.id();
        vm.prank(mmAllocator);
        metaMorpho.setSupplyQueue(supplyQueue);
    }

    function setSupplyQueueAllMarkets() public {
        Id[] memory supplyQueue = new Id[](MM_NB_MARKETS);
        for (uint256 i; i < MM_NB_MARKETS; i++) {
            MarketParams memory marketParams = allMarketParams[i];
            setMetaMorphoCap(marketParams, CAP);
            supplyQueue[i] = marketParams.id();
        }
        vm.prank(mmAllocator);
        metaMorpho.setSupplyQueue(supplyQueue);
    }

    function setMetaMorphoCap(MarketParams memory marketParams, uint256 newCap) internal {
        vm.prank(mmCurator);
        metaMorpho.submitCap(marketParams, newCap);
        vm.warp(block.timestamp + metaMorpho.timelock());
        metaMorpho.acceptCap(marketParams);
    }
}
