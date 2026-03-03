// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Morpho Association
pragma solidity ^0.8.0;

import "../BaseTest.sol";

import {
    OracleMock,
    IrmMock,
    IMorpho,
    IMetaMorphoV1_1,
    ORACLE_PRICE_SCALE,
    MarketParams,
    MarketParamsLib,
    Id,
    MorphoBalancesLib
} from "../../lib/metamorpho-v1.1/test/forge/helpers/IntegrationTest.sol";

import {IVaultV2Factory} from "../../src/interfaces/IVaultV2Factory.sol";
import {IVaultV2} from "../../src/interfaces/IVaultV2.sol";

import {VaultV2Factory} from "../../src/VaultV2Factory.sol";
import "../../src/VaultV2.sol";
import "../../src/adapters/MorphoVaultV1Adapter.sol";
import {MorphoVaultV1AdapterFactory} from "../../src/adapters/MorphoVaultV1AdapterFactory.sol";
import {IMorphoVaultV1AdapterFactory} from "../../src/adapters/interfaces/IMorphoVaultV1AdapterFactory.sol";
import {IMorphoVaultV1Adapter} from "../../src/adapters/interfaces/IMorphoVaultV1Adapter.sol";

// TEST WITH DECIMALS = 16
contract MorphoVaultV1_1IntegrationSharePriceTest is BaseTest {
    using MarketParamsLib for MarketParams;

    address immutable borrower = makeAddr("borrower");

    uint256 internal maxTestAssets;

    // Morpho.
    address internal immutable morphoOwner = makeAddr("MorphoOwner");
    IMorpho internal morpho;
    ERC20Mock internal collateralToken;
    OracleMock internal oracle;
    IrmMock internal irm;
    uint256 lltv = 0.8 ether;

    // Morpho Vault V1.
    IMetaMorphoV1_1 internal morphoVaultV1;
    uint256 internal constant CAP = 1e18;
    MarketParams internal marketParams;

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

        vm.startPrank(morphoOwner);
        morpho.enableIrm(address(irm));
        morpho.enableLltv(lltv);
        vm.stopPrank();

        marketParams = MarketParams({
            loanToken: address(underlyingToken),
            collateralToken: address(collateralToken),
            oracle: address(oracle),
            irm: address(irm),
            lltv: lltv
        });

        morpho.createMarket(marketParams);

        // Setup morphoVaultV1.
        morphoVaultV1 = IMetaMorphoV1_1(
            deployCode(
                "MetaMorphoV1_1.sol",
                abi.encode(owner, address(morpho), 0, address(underlyingToken), "morphoVaultV1", "MV1")
            )
        );

        vm.prank(owner);
        morphoVaultV1.submitCap(marketParams, type(uint184).max);
        morphoVaultV1.acceptCap(marketParams);

        Id[] memory supplyQueue = new Id[](1);
        supplyQueue[0] = marketParams.id();
        vm.prank(owner);
        morphoVaultV1.setSupplyQueue(supplyQueue);

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
        vault.setLiquidityAdapterAndData(address(morphoVaultV1Adapter), hex"");

        vm.prank(allocator);
        vault.setMaxRate(MAX_MAX_RATE);

        increaseAbsoluteCap(idData, type(uint128).max);
        increaseRelativeCap(idData, 1e18);

        // Tokens
        deal(address(underlyingToken), address(this), type(uint256).max);
        underlyingToken.approve(address(vault), type(uint256).max);
        underlyingToken.approve(address(morphoVaultV1), type(uint256).max);
        underlyingToken.approve(address(morpho), type(uint256).max);

        console.log("token decimals", underlyingToken.decimals());
    }

    /// forge-config: default.isolate = true
    function testSharePriceSlightyAboveOne() public {
        morphoVaultV1.deposit(0.01e18, address(this));
        morpho.supply(marketParams, 1e18, 0, address(morphoVaultV1), hex"");
        assertGt(morphoVaultV1.totalAssets(), morphoVaultV1.totalSupply(), "share price should be > 1");
        sharePriceAttack(0);
    }

    /// forge-config: default.isolate = true
    function testSharePriceSightlyBelowOne() public {
        morphoVaultV1.deposit(0.01e18, address(this));
        morpho.supply(marketParams, 0.98e18, 0, address(morphoVaultV1), hex"");
        assertLt(morphoVaultV1.totalAssets(), morphoVaultV1.totalSupply(), "share price should be < 1");
        sharePriceAttack(1);
    }

    /// forge-config: default.isolate = true
    function testSharePriceSlightyBelowOneTenth() public {
        morphoVaultV1.deposit(0.01e18, address(this));
        morpho.supply(marketParams, 0.089e18, 0, address(morphoVaultV1), hex"");
        assertLt(10 * morphoVaultV1.totalAssets(), morphoVaultV1.totalSupply(), "share price should be < 1/10");
        sharePriceAttack(10);
    }

    function sharePriceAttack(uint256 priceMode) public {
        uint256 virtualShares = 10 ** (18 - underlyingTokenDecimals);
        uint256 totalVirtualShares = virtualShares;
        assertEq(vault.totalAssets(), 0, "total assets before");
        assertEq(vault.totalSupply(), totalVirtualShares - virtualShares, "total supply before");

        for (uint256 i = 0; i < 20; i++) {
            this.inflateShares(priceMode, i);

            totalVirtualShares *= 2;
            assertEq(vault.totalAssets(), 0, "total assets");
            assertEq(vault.totalSupply(), totalVirtualShares - virtualShares, "total supply");
        }
    }

    function inflateShares(uint256 priceMode, uint256 j) public {
        vault.deposit(1, address(this));
        for (uint256 i; i < priceMode; i++) {
            vault.deposit(1, address(this));
        }
        for (uint256 i; i < priceMode; i++) {
            vault.withdraw(1, address(this), address(this));
        }
    }
}
