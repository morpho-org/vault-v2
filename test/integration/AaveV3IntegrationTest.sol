// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import "../BaseTest.sol";

import {AaveV3Adapter} from "../../src/adapters/AaveV3Adapter.sol";
import {AaveV3AdapterFactory} from "../../src/adapters/AaveV3AdapterFactory.sol";
import {IAaveV3AdapterFactory} from "../../src/adapters/interfaces/IAaveV3AdapterFactory.sol";
import {IAaveV3Adapter} from "../../src/adapters/interfaces/IAaveV3Adapter.sol";
import {IERC20} from "../../src/interfaces/IERC20.sol";
import {MathLib} from "../../src/libraries/MathLib.sol";
import {WAD, MAX_MAX_RATE} from "../../src/VaultV2.sol";

/// @notice Integration test for Aave V3 Adapter using mainnet fork
contract AaveV3IntegrationTest is BaseTest {
    using MathLib for uint256;

    // Aave V3 Mainnet addresses
    address internal constant AAVE_V3_POOL = 0x87870Bca3F3fD6335C3F4ce8392D69350B4fA4E2;
    address internal constant USDT = 0xdAC17F958D2ee523a2206206994597C13D831ec7;
    address internal constant aUSDT = 0x23878914EFE38d27C4D67Ab83ed1b93A74D4086a;

    // USDT whale for dealing tokens
    address internal constant USDT_WHALE = 0xF977814e90dA44bFA03b6295A0616a897441aceC; // Binance

    IAaveV3AdapterFactory internal aaveFactory;
    IAaveV3Adapter internal aaveAdapter;

    bytes internal aaveAdapterIdData;
    bytes32 internal aaveAdapterId;

    uint256 internal constant MIN_TEST_ASSETS = 100e6; // 100 USDT
    uint256 internal constant MAX_TEST_ASSETS = 1_000_000e6; // 1M USDT

    // Tolerance for aToken rounding (1 wei per operation)
    uint256 internal constant ATOKEN_ROUNDING_TOLERANCE = 2;

    function setUp() public virtual override {
        // Fork mainnet
        string memory rpcUrl = vm.envOr("ETH_RPC_URL", string(""));
        if (bytes(rpcUrl).length == 0) {
            // Skip test if no RPC URL provided
            return;
        }
        vm.createSelectFork(rpcUrl);

        // Setup USDT as underlying token (6 decimals)
        underlyingTokenDecimals = 6;
        underlyingToken = ERC20Mock(USDT);

        // Deploy vault factory and vault
        vaultFactory = IVaultV2Factory(address(new VaultV2Factory()));
        vault = IVaultV2(vaultFactory.createVaultV2(owner, address(underlyingToken), bytes32(0)));
        vm.label(address(vault), "vault");

        // Setup roles
        vm.startPrank(owner);
        vault.setCurator(curator);
        vault.setIsSentinel(sentinel, true);
        vm.stopPrank();

        vm.prank(curator);
        vault.submit(abi.encodeCall(IVaultV2.setIsAllocator, (allocator, true)));
        vault.setIsAllocator(allocator, true);

        // Deploy Aave adapter
        aaveFactory = new AaveV3AdapterFactory(AAVE_V3_POOL);
        aaveAdapter = IAaveV3Adapter(aaveFactory.createAaveV3Adapter(address(vault), aUSDT));
        vm.label(address(aaveAdapter), "aaveAdapter");

        aaveAdapterIdData = abi.encode("this", address(aaveAdapter));
        aaveAdapterId = keccak256(aaveAdapterIdData);

        // Add adapter to vault
        vm.prank(curator);
        vault.submit(abi.encodeCall(IVaultV2.addAdapter, (address(aaveAdapter))));
        vault.addAdapter(address(aaveAdapter));

        // Set max rate
        vm.prank(allocator);
        vault.setMaxRate(MAX_MAX_RATE);

        // Set caps
        increaseAbsoluteCap(aaveAdapterIdData, type(uint128).max);
        increaseRelativeCap(aaveAdapterIdData, WAD);

        // Deal USDT from whale
        vm.prank(USDT_WHALE);
        (bool success,) = USDT.call(abi.encodeWithSignature("transfer(address,uint256)", address(this), 10_000_000e6));
        require(success, "USDT transfer failed");

        // USDT approve doesn't return bool, use low-level call
        (success,) = USDT.call(abi.encodeWithSignature("approve(address,uint256)", address(vault), type(uint256).max));
        require(success, "USDT approve failed");
    }

    modifier skipIfNoFork() {
        string memory rpcUrl = vm.envOr("ETH_RPC_URL", string(""));
        if (bytes(rpcUrl).length == 0) {
            return;
        }
        _;
    }

    function _logUsdt(string memory label, uint256 amount) internal pure {
        console.log(string.concat(label, ":"), amount / 1e6, "USDT", string.concat("(", vm.toString(amount), " wei)"));
    }

    function _logHeader(string memory title) internal pure {
        console.log("");
        console.log("================================================================================");
        console.log(title);
        console.log("================================================================================");
    }

    function _logSection(string memory title) internal pure {
        console.log("");
        console.log(string.concat("--- ", title, " ---"));
    }

    function testAaveAdapterSetup() public skipIfNoFork {
        _logHeader("TEST: Aave Adapter Setup");

        console.log("Aave V3 Pool:  ", aaveAdapter.aavePool());
        console.log("aToken (aUSDT):", aaveAdapter.aToken());
        console.log("Asset (USDT):  ", aaveAdapter.asset());
        console.log("Parent Vault:  ", aaveAdapter.parentVault());

        assertEq(aaveAdapter.aavePool(), AAVE_V3_POOL, "Incorrect Aave pool");
        assertEq(aaveAdapter.aToken(), aUSDT, "Incorrect aToken");
        assertEq(aaveAdapter.asset(), USDT, "Incorrect asset");
        assertEq(aaveAdapter.parentVault(), address(vault), "Incorrect parent vault");

        console.log("");
        console.log("[OK] All adapter configurations verified");
    }

    function testDepositAndAllocateToAave() public skipIfNoFork {
        _logHeader("TEST: Deposit and Allocate to Aave");

        uint256 depositAmount = 10_000e6; // 10,000 USDT

        _logSection("Step 1: Deposit to Vault");
        _logUsdt("  Deposit amount", depositAmount);
        vault.deposit(depositAmount, address(this));
        _logUsdt("  Vault USDT balance", IERC20(USDT).balanceOf(address(vault)));
        assertEq(IERC20(USDT).balanceOf(address(vault)), depositAmount, "Vault should have USDT");

        _logSection("Step 2: Allocate to Aave");
        vm.prank(allocator);
        vault.allocate(address(aaveAdapter), hex"", depositAmount);

        _logSection("Results");
        _logUsdt("  Vault USDT balance", IERC20(USDT).balanceOf(address(vault)));
        _logUsdt("  Adapter aUSDT balance", IERC20(aUSDT).balanceOf(address(aaveAdapter)));
        _logUsdt("  Vault allocation", vault.allocation(aaveAdapterId));

        // Verify (aToken rounding may cause 1 wei difference)
        assertEq(IERC20(USDT).balanceOf(address(vault)), 0, "Vault should have no USDT after allocation");
        assertApproxEqAbs(
            IERC20(aUSDT).balanceOf(address(aaveAdapter)),
            depositAmount,
            ATOKEN_ROUNDING_TOLERANCE,
            "Adapter should have aUSDT"
        );
        assertApproxEqAbs(
            vault.allocation(aaveAdapterId), depositAmount, ATOKEN_ROUNDING_TOLERANCE, "Allocation should be tracked"
        );

        console.log("");
        console.log("[OK] Deposit and allocation successful");
    }

    function testWithdrawFromAave() public skipIfNoFork {
        _logHeader("TEST: Withdraw from Aave");

        uint256 depositAmount = 10_000e6;
        uint256 withdrawAmount = 5_000e6;

        _logSection("Setup: Deposit and Allocate");
        _logUsdt("  Deposit amount", depositAmount);
        vault.deposit(depositAmount, address(this));
        vm.prank(allocator);
        vault.allocate(address(aaveAdapter), hex"", depositAmount);
        _logUsdt("  Initial allocation", vault.allocation(aaveAdapterId));

        _logSection("Deallocate from Aave");
        _logUsdt("  Withdraw amount", withdrawAmount);
        vm.prank(allocator);
        vault.deallocate(address(aaveAdapter), hex"", withdrawAmount);

        _logSection("Results");
        _logUsdt("  Vault USDT balance", IERC20(USDT).balanceOf(address(vault)));
        _logUsdt("  Remaining allocation", vault.allocation(aaveAdapterId));

        // Verify (aToken rounding may cause 1 wei difference)
        assertEq(IERC20(USDT).balanceOf(address(vault)), withdrawAmount, "Vault should have withdrawn USDT");
        assertApproxEqAbs(
            vault.allocation(aaveAdapterId),
            depositAmount - withdrawAmount,
            ATOKEN_ROUNDING_TOLERANCE,
            "Allocation should decrease"
        );

        console.log("");
        console.log("[OK] Withdrawal successful");
    }

    function testInterestAccrual() public skipIfNoFork {
        _logHeader("TEST: Interest Accrual (1 Year Simulation)");

        uint256 depositAmount = 100_000e6; // 100,000 USDT

        _logSection("Setup: Deposit and Allocate");
        _logUsdt("  Deposit amount", depositAmount);
        vault.deposit(depositAmount, address(this));
        vm.prank(allocator);
        vault.allocate(address(aaveAdapter), hex"", depositAmount);

        uint256 realAssetsBefore = aaveAdapter.realAssets();
        _logUsdt("  Real assets before", realAssetsBefore);

        _logSection("Time Skip: 365 days");
        skip(365 days);

        uint256 realAssetsAfter = aaveAdapter.realAssets();

        _logSection("Interest Calculation");
        _logUsdt("  Real assets after", realAssetsAfter);
        _logUsdt("  Interest earned", realAssetsAfter - realAssetsBefore);

        uint256 aprBps = ((realAssetsAfter - realAssetsBefore) * 10000) / realAssetsBefore;
        console.log(string.concat("  APR (estimated): ", vm.toString(aprBps / 100), ".", vm.toString(aprBps % 100), "%"));

        // Interest should have accrued (aToken balance increases automatically)
        assertGe(realAssetsAfter, realAssetsBefore, "realAssets should increase or stay same");

        console.log("");
        console.log("[OK] Interest accrual verified");
    }

    function testFullDepositWithdrawCycle() public skipIfNoFork {
        _logHeader("TEST: Full Deposit/Withdraw Cycle (30 Days)");

        uint256 depositAmount = 50_000e6; // 50,000 USDT
        uint256 balanceBefore = IERC20(USDT).balanceOf(address(this));

        _logSection("Step 1: Deposit to Vault");
        _logUsdt("  Deposit amount", depositAmount);
        vault.deposit(depositAmount, address(this));

        _logSection("Step 2: Allocate to Aave");
        vm.prank(allocator);
        vault.allocate(address(aaveAdapter), hex"", depositAmount);
        _logUsdt("  Allocated", vault.allocation(aaveAdapterId));

        _logSection("Step 3: Time Skip (30 days)");
        skip(30 days);
        console.log("  Simulating 30 days passage...");

        _logSection("Step 4: Accrue Interest");
        vault.accrueInterest();
        uint256 realAssets = aaveAdapter.realAssets();
        _logUsdt("  Real assets after interest", realAssets);

        _logSection("Step 5: Deallocate from Aave");
        vm.prank(allocator);
        vault.deallocate(address(aaveAdapter), hex"", realAssets);
        _logUsdt("  Vault USDT balance", IERC20(USDT).balanceOf(address(vault)));

        _logSection("Step 6: Redeem Shares");
        uint256 shares = vault.balanceOf(address(this));
        console.log("  Shares to redeem:", shares);
        vault.redeem(shares, address(this), address(this));

        uint256 balanceAfter = IERC20(USDT).balanceOf(address(this));

        _logSection("Final Results");
        _logUsdt("  Balance before cycle", balanceBefore);
        _logUsdt("  Balance after cycle", balanceAfter);

        int256 profit = int256(balanceAfter) - int256(balanceBefore - depositAmount);
        if (profit >= 0) {
            _logUsdt("  PROFIT", uint256(profit));
        } else {
            _logUsdt("  LOSS", uint256(-profit));
        }

        console.log("");
        console.log("[OK] Full cycle completed successfully");
    }

    function testMultipleAllocationsAndDeallocations() public skipIfNoFork {
        _logHeader("TEST: Multiple Allocations and Deallocations");

        uint256 amount1 = 10_000e6;
        uint256 amount2 = 20_000e6;
        uint256 amount3 = 15_000e6;

        _logSection("Setup: Deposit Total");
        _logUsdt("  Total deposit", amount1 + amount2 + amount3);
        vault.deposit(amount1 + amount2 + amount3, address(this));

        vm.startPrank(allocator);

        _logSection("Allocation Round 1");
        _logUsdt("  Allocating", amount1);
        vault.allocate(address(aaveAdapter), hex"", amount1);
        _logUsdt("  Total allocation", vault.allocation(aaveAdapterId));
        assertApproxEqAbs(vault.allocation(aaveAdapterId), amount1, ATOKEN_ROUNDING_TOLERANCE);

        _logSection("Allocation Round 2");
        _logUsdt("  Allocating", amount2);
        vault.allocate(address(aaveAdapter), hex"", amount2);
        _logUsdt("  Total allocation", vault.allocation(aaveAdapterId));
        assertApproxEqAbs(vault.allocation(aaveAdapterId), amount1 + amount2, ATOKEN_ROUNDING_TOLERANCE * 2);

        _logSection("Allocation Round 3");
        _logUsdt("  Allocating", amount3);
        vault.allocate(address(aaveAdapter), hex"", amount3);
        _logUsdt("  Total allocation", vault.allocation(aaveAdapterId));
        assertApproxEqAbs(vault.allocation(aaveAdapterId), amount1 + amount2 + amount3, ATOKEN_ROUNDING_TOLERANCE * 3);

        _logSection("Deallocation Round 1");
        _logUsdt("  Deallocating", amount1);
        vault.deallocate(address(aaveAdapter), hex"", amount1);
        _logUsdt("  Remaining allocation", vault.allocation(aaveAdapterId));
        assertApproxEqAbs(vault.allocation(aaveAdapterId), amount2 + amount3, ATOKEN_ROUNDING_TOLERANCE * 4);

        _logSection("Deallocation Round 2 (Remaining)");
        uint256 remaining = vault.allocation(aaveAdapterId);
        _logUsdt("  Deallocating remaining", remaining);
        vault.deallocate(address(aaveAdapter), hex"", remaining);
        _logUsdt("  Final allocation", vault.allocation(aaveAdapterId));
        assertEq(vault.allocation(aaveAdapterId), 0);

        vm.stopPrank();

        console.log("");
        console.log("[OK] Multiple allocations/deallocations successful");
    }

    function testSetLiquidityAdapter() public skipIfNoFork {
        _logHeader("TEST: Auto-Allocation via Liquidity Adapter");

        uint256 depositAmount = 10_000e6;

        _logSection("Setup: Set Aave as Liquidity Adapter");
        vm.prank(allocator);
        vault.setLiquidityAdapterAndData(address(aaveAdapter), hex"");
        console.log("  Liquidity adapter set to Aave");

        _logSection("Deposit (Auto-Allocates to Aave)");
        _logUsdt("  Deposit amount", depositAmount);
        vault.deposit(depositAmount, address(this));

        _logSection("Results");
        _logUsdt("  Vault idle USDT", IERC20(USDT).balanceOf(address(vault)));
        _logUsdt("  Auto-allocated to Aave", vault.allocation(aaveAdapterId));

        // Verify allocation happened
        assertGe(vault.allocation(aaveAdapterId), depositAmount - 1, "Should be allocated to Aave");
        assertLe(IERC20(USDT).balanceOf(address(vault)), 1, "Vault should have minimal idle");

        console.log("");
        console.log("[OK] Auto-allocation via liquidity adapter working");
    }

    function testFuzzAllocateDeallocate(uint256 allocateAmount, uint256 deallocatePercent) public skipIfNoFork {
        // Note: Fuzz test runs 2048 times, logging disabled for performance
        allocateAmount = bound(allocateAmount, MIN_TEST_ASSETS, MAX_TEST_ASSETS);
        deallocatePercent = bound(deallocatePercent, 0, 100);

        // Deposit
        vault.deposit(allocateAmount, address(this));

        // Allocate
        vm.prank(allocator);
        vault.allocate(address(aaveAdapter), hex"", allocateAmount);

        uint256 allocationBefore = vault.allocation(aaveAdapterId);
        assertApproxEqAbs(allocationBefore, allocateAmount, ATOKEN_ROUNDING_TOLERANCE);

        // Deallocate based on actual allocation to avoid rounding issues
        uint256 deallocateAmount = (allocationBefore * deallocatePercent) / 100;

        vm.prank(allocator);
        vault.deallocate(address(aaveAdapter), hex"", deallocateAmount);

        uint256 allocationAfter = vault.allocation(aaveAdapterId);
        assertApproxEqAbs(allocationAfter, allocationBefore - deallocateAmount, ATOKEN_ROUNDING_TOLERANCE);
    }
}
