// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Morpho Association
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

import {VaultV2Factory} from "../../src/VaultV2Factory.sol";
import "../../src/VaultV2.sol";
import {MorphoVaultV1Adapter} from "../../src/adapters/MorphoVaultV1Adapter.sol";
import {MorphoVaultV1AdapterFactory} from "../../src/adapters/MorphoVaultV1AdapterFactory.sol";
import {IMorphoVaultV1AdapterFactory} from "../../src/adapters/interfaces/IMorphoVaultV1AdapterFactory.sol";
import {IMorphoVaultV1Adapter} from "../../src/adapters/interfaces/IMorphoVaultV1Adapter.sol";

contract MorphoVaultV1IntegrationTest is BaseTest {
    using MarketParamsLib for MarketParams;

    uint256 internal maxTestAssets;

    // Morpho.
    address internal immutable morphoOwner = makeAddr("MorphoOwner");
    IMorpho internal morpho;
    ERC20Mock internal collateralToken;
    OracleMock internal oracle;
    IrmMock internal irm;

    // Morpho Vault V1.
    IMetaMorpho internal morphoVaultV1;
    address internal immutable mmOwner = makeAddr("mmOwner");
    address internal immutable mmAllocator = makeAddr("mmAllocator");
    address internal immutable mmCurator = makeAddr("mmCurator");
    uint256 internal constant MORPHO_VAULT_V1_NB_MARKETS = 5;
    uint256 internal constant CAP = 1e18;
    uint256 internal constant MORPHO_VAULT_V1_TIMELOCK = 1 weeks;
    MarketParams[] internal allMarketParams;
    MarketParams internal idleParams;

    // Adapter.
    IMorphoVaultV1AdapterFactory internal morphoVaultV1AdapterFactory;
    IMorphoVaultV1Adapter internal morphoVaultV1Adapter;

    function setUp() public virtual override {
        super.setUp();

        maxTestAssets = 10 ** min(18 + underlyingToken.decimals(), 32);

        // Setup morpho.
        morpho = IMorpho(deployCode("Morpho.sol", abi.encode(morphoOwner)));
        collateralToken = new ERC20Mock(18);
        oracle = new OracleMock();
        irm = new IrmMock();

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

        for (uint256 i; i < MORPHO_VAULT_V1_NB_MARKETS; ++i) {
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

        // Setup morphoVaultV1.
        morphoVaultV1 = IMetaMorpho(
            deployCode(
                "MetaMorpho.sol",
                abi.encode(
                    mmOwner, address(morpho), MORPHO_VAULT_V1_TIMELOCK, address(underlyingToken), "morphoVaultV1", "MV1"
                )
            )
        );
        vm.startPrank(mmOwner);
        morphoVaultV1.setCurator(mmCurator);
        morphoVaultV1.setIsAllocator(mmAllocator, true);
        vm.stopPrank();

        // Setup morphoVaultV1Adapter and vault.
        morphoVaultV1AdapterFactory = new MorphoVaultV1AdapterFactory();
        morphoVaultV1Adapter = MorphoVaultV1Adapter(
            morphoVaultV1AdapterFactory.createMorphoVaultV1Adapter(address(vault), address(morphoVaultV1))
        );

        bytes memory idData = abi.encode("this", address(morphoVaultV1Adapter));
        vm.prank(curator);
        vault.submit(abi.encodeCall(IVaultV2.addAdapter, (address(morphoVaultV1Adapter))));
        vault.addAdapter(address(morphoVaultV1Adapter));

        vm.prank(allocator);
        vault.setMaxRate(MAX_MAX_RATE);

        increaseAbsoluteCap(idData, type(uint128).max);
        increaseRelativeCap(idData, 1e18);

        // Approval.
        deal(address(underlyingToken), address(this), type(uint256).max);
        underlyingToken.approve(address(vault), type(uint256).max);
    }

    function setSupplyQueueIdle() internal {
        setMorphoVaultV1Cap(idleParams, type(uint184).max);
        Id[] memory supplyQueue = new Id[](1);
        supplyQueue[0] = idleParams.id();
        vm.prank(mmAllocator);
        morphoVaultV1.setSupplyQueue(supplyQueue);
    }

    function setSupplyQueueAllMarkets() internal {
        Id[] memory supplyQueue = new Id[](MORPHO_VAULT_V1_NB_MARKETS);
        for (uint256 i; i < MORPHO_VAULT_V1_NB_MARKETS; i++) {
            MarketParams memory marketParams = allMarketParams[i];
            setMorphoVaultV1Cap(marketParams, CAP);
            supplyQueue[i] = marketParams.id();
        }
        vm.prank(mmAllocator);
        morphoVaultV1.setSupplyQueue(supplyQueue);
    }

    function setMorphoVaultV1Cap(MarketParams memory marketParams, uint256 newCap) internal {
        vm.prank(mmCurator);
        morphoVaultV1.submitCap(marketParams, newCap);
        skip(morphoVaultV1.timelock());
        morphoVaultV1.acceptCap(marketParams);
    }
}
