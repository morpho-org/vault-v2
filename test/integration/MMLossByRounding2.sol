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

contract MMDonationAttackTest is Test {
    using MarketParamsLib for MarketParams;

    // The packed slot containing both _totalAssets and lastUpdate.
    bytes32 TOTAL_ASSETS_AND_LAST_UPDATE_PACKED_SLOT = bytes32(uint256(13));

    // Asset
    ERC20Mock asset;

    // Vault
    IVaultV2 vault;

    // Morpho.
    IMorpho internal morpho;
    ERC20Mock internal collateralToken;
    OracleMock internal oracle;
    IrmMock internal irm;

    // MetaMorpho.
    IMetaMorpho internal metaMorpho;
    uint256 internal constant CAP = 1e18;
    MarketParams[] internal allMarketParams;
    MarketParams internal idleParams;
    uint256 internal constant MM_TIMELOCK = 1 weeks;

    // Attacker
    address eve = makeAddr("eve");

    // Adapter.
    MetaMorphoAdapterFactory internal metaMorphoAdapterFactory;
    MetaMorphoAdapter internal metaMorphoAdapter;

    function setUp() public virtual {
        // Asset
        asset = new ERC20Mock();

        // Vault
        vault = new VaultV2(address(this), address(asset));
        vault.setCurator(address(this));
        vault.setIsSentinel(address(this), true);

        vault.submit(abi.encodeCall(IVaultV2.setIsAllocator, (address(this), true)));
        vault.setIsAllocator(address(this), true);

        // Morpho
        morpho = IMorpho(deployCode("Morpho.sol", abi.encode(address(this))));
        collateralToken = new ERC20Mock();
        oracle = new OracleMock();
        irm = new IrmMock();
        oracle.setPrice(ORACLE_PRICE_SCALE);
        irm.setApr(0.5 ether); // 50%.

        idleParams = MarketParams({
            loanToken: address(asset),
            collateralToken: address(0),
            oracle: address(0),
            irm: address(irm),
            lltv: 0
        });

        morpho.enableIrm(address(irm));
        morpho.enableLltv(0);
        morpho.createMarket(idleParams);
        allMarketParams.push(idleParams);

        // MetaMorpho.
        metaMorpho = IMetaMorpho(
            deployCode(
                "MetaMorpho.sol",
                abi.encode(address(this), address(morpho), MM_TIMELOCK, address(asset), "metamorpho", "MM")
            )
        );
        metaMorpho.setCurator(address(this));
        metaMorpho.setIsAllocator(address(this), true);
        // MetaMorpho supply queue
        metaMorpho.submitCap(idleParams, type(uint184).max);
        skip(metaMorpho.timelock());
        metaMorpho.acceptCap(idleParams);
        Id[] memory supplyQueue = new Id[](1);
        supplyQueue[0] = idleParams.id();
        metaMorpho.setSupplyQueue(supplyQueue);

        // MetaMorphoAdapter and vault
        metaMorphoAdapter = new MetaMorphoAdapter(address(vault), address(metaMorpho));
        bytes memory idData = abi.encode("adapter", address(metaMorphoAdapter));
        vault.submit(abi.encodeCall(IVaultV2.setIsAdapter, (address(metaMorphoAdapter), true)));
        vault.submit(abi.encodeCall(IVaultV2.increaseAbsoluteCap, (idData, type(uint128).max)));
        vault.submit(abi.encodeCall(IVaultV2.increaseRelativeCap, (idData, WAD)));

        vault.setIsAdapter(address(metaMorphoAdapter), true);
        vault.increaseAbsoluteCap(idData, type(uint128).max);
        vault.increaseRelativeCap(idData, WAD);

        vault.setLiquidityMarket(address(metaMorphoAdapter), "");

        // Label
        vm.label(address(this), "testContract");
        vm.label(address(asset), "asset");
        vm.label(address(vault), "vault");
    }

    uint256 SEED = 1e5;
    uint256 EVE_MM_OWNERSHIP_PERCENT = WAD - WAD / 100;
    uint256 EVE_DEPOSIT = EVE_MM_OWNERSHIP_PERCENT * SEED / (WAD - EVE_MM_OWNERSHIP_PERCENT);
    uint256 HIGH_SHARE_PRICE = 1e4;
    uint256 DONATION = (SEED + EVE_DEPOSIT) * (HIGH_SHARE_PRICE - 1);
    uint256 FLASHLOAN = type(uint128).max;

    function testLossByDeposit2() public {
        // Seed
        address seeder = makeAddr("seeder");
        deal(address(asset), seeder, SEED);
        vm.startPrank(seeder);
        asset.approve(address(metaMorpho), type(uint256).max);
        metaMorpho.deposit(SEED, address(this));
        vm.stopPrank();

        // Check share price before
        assertEq(metaMorpho.previewRedeem(SEED), SEED, "share price before donation");

        // Attacker
        deal(address(asset), eve, FLASHLOAN);

        uint256 usedFlashloan;

        // Take a big position in metaMorpho
        vm.startPrank(eve);
        asset.approve(address(metaMorpho), type(uint256).max);
        metaMorpho.deposit(EVE_DEPOSIT, eve);
        vm.stopPrank();

        // Donate
        vm.startPrank(eve);
        asset.approve(address(morpho), type(uint256).max);
        asset.approve(address(vault), type(uint256).max);
        (, uint256 mintedShares) = morpho.supply(idleParams, DONATION, 0, address(metaMorpho), hex"");
        vm.stopPrank();
        usedFlashloan += DONATION;

        // Check share price increase
        assertApproxEqRel(
            metaMorpho.previewRedeem(SEED), SEED * HIGH_SHARE_PRICE, WAD / 1e4, "share price after donation"
        );

        uint256 balanceBefore = metaMorpho.balanceOf(address(vault));
        uint256 gasUsed = 0;
        uint256 iterations;

        vm.startPrank(eve);
        uint256 sharePrice = HIGH_SHARE_PRICE;
        // bytes32 free_mem;
        // assembly { free_mem := mload(0x40) }
        while (eveBalance() < FLASHLOAN) {
            console.log("-------------");
            console.log("iteration     %s", iterations);
            console.log("eve assets    %s", asset.balanceOf(eve));
            console.log("eve vault pos %s", vault.previewRedeem(vault.balanceOf(eve)));
            console.log("eve mm pos    %s", metaMorpho.previewRedeem(metaMorpho.balanceOf(eve)));
            console.log("eve loss      %s", FLASHLOAN - eveBalance());
            console.log("share price   %s", sharePrice);
            // console.log("mm total assets %e",metaMorpho.lastTotalAssets());
            console.log("-------------");
            iterations++;
            vault.deposit(sharePrice - 1, address(eve));
            usedFlashloan += sharePrice - 1;
            gasUsed += vm.lastCallGas().gasTotalUsed;

            assertEq(metaMorpho.balanceOf(address(vault)), balanceBefore, "no shares gained");
            sharePrice = metaMorpho.previewRedeem(1);
            // assembly ("memory-safe") { mstore(0x40, free_mem) }
        }
        vm.stopPrank();
        console.log(FLASHLOAN);
        console.log(eveBalance());
        console.log("%s iterations", iterations);
        console.log("%e gas used", gasUsed);
        console.log("%e used flashloan", usedFlashloan);
    }

    function eveBalance() internal view returns (uint256) {
        return asset.balanceOf(eve) + metaMorpho.previewRedeem(metaMorpho.balanceOf(eve))
            + vault.previewRedeem(vault.balanceOf(eve));
    }

    // Seed with 1e5 WBTC
    // Donate so price goes x30
    // Someone deposits sharePrice - 1
    // Note I can withdraw from the vault, donate to MM, then deposit again as its share price has not changed. (this is
    // for deallocate)
    // Or I can withdraw from the vault and then deposit again (allocate attack)
    // Note you can also do the attack by allocation
    // You can just deposit, and when the attack is halfway done you redeem all your vault shares.
}
