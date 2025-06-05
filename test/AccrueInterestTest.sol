// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import "./BaseTest.sol";

contract BurnsAllGas {
    fallback() external {
        assembly {
            invalid()
        }
    }
}

// Gate that consume a sensible amount of gas and return true.
contract Gate {
    fallback() external {
        assembly {
            mstore(100000, 1) // consumes ~28k gas
            mstore(0, 1)
            return(0, 32)
        }
    }
}

contract AccrueInterestTest is BaseTest {
    using MathLib for uint256;

    address performanceFeeRecipient = makeAddr("performanceFeeRecipient");
    address managementFeeRecipient = makeAddr("managementFeeRecipient");
    uint256 constant MAX_TEST_ASSETS = 1e36;

    function setUp() public override {
        super.setUp();

        vm.startPrank(curator);
        vault.submit(abi.encodeCall(IVaultV2.setPerformanceFeeRecipient, (performanceFeeRecipient)));
        vault.submit(abi.encodeCall(IVaultV2.setManagementFeeRecipient, (managementFeeRecipient)));
        vm.stopPrank();

        vault.setPerformanceFeeRecipient(performanceFeeRecipient);
        vault.setManagementFeeRecipient(managementFeeRecipient);

        deal(address(underlyingToken), address(this), type(uint256).max);
        underlyingToken.approve(address(vault), type(uint256).max);
    }

    function testAccrueInterestView(
        uint256 deposit,
        uint256 performanceFee,
        uint256 managementFee,
        uint256 interestPerSecond,
        uint256 elapsed
    ) public {
        deposit = bound(deposit, 0, MAX_TEST_ASSETS);
        performanceFee = bound(performanceFee, 0, MAX_PERFORMANCE_FEE);
        managementFee = bound(managementFee, 0, MAX_MANAGEMENT_FEE);
        interestPerSecond = bound(interestPerSecond, 0, deposit.mulDivDown(MAX_RATE_PER_SECOND, WAD));
        elapsed = bound(elapsed, 0, 20 * 365 days);

        // Setup.
        vm.prank(allocator);
        vic.increaseInterestPerSecond(interestPerSecond);
        vm.startPrank(curator);
        vault.submit(abi.encodeCall(IVaultV2.setPerformanceFee, (performanceFee)));
        vault.submit(abi.encodeCall(IVaultV2.setManagementFee, (managementFee)));
        vm.stopPrank();
        vault.setPerformanceFee(performanceFee);
        vault.setManagementFee(managementFee);

        vault.deposit(deposit, address(this));

        vm.warp(vm.getBlockTimestamp() + elapsed);

        // Normal path.
        (uint256 newTotalAssets, uint256 performanceFeeShares, uint256 managementFeeShares) = vault.accrueInterestView();
        vault.accrueInterest();
        assertEq(newTotalAssets, vault.totalAssets());
        assertEq(performanceFeeShares, vault.balanceOf(performanceFeeRecipient));
        assertEq(managementFeeShares, vault.balanceOf(managementFeeRecipient));
    }

    function testAccrueInterest(
        uint256 deposit,
        uint256 performanceFee,
        uint256 managementFee,
        uint256 interestPerSecond,
        uint256 elapsed
    ) public {
        performanceFee = bound(performanceFee, 0, MAX_PERFORMANCE_FEE);
        managementFee = bound(managementFee, 0, MAX_MANAGEMENT_FEE);
        deposit = bound(deposit, 0, MAX_TEST_ASSETS);
        interestPerSecond = bound(interestPerSecond, 0, deposit.mulDivDown(MAX_RATE_PER_SECOND, WAD));
        elapsed = bound(elapsed, 1, 20 * 365 days);

        // Setup.
        vault.deposit(deposit, address(this));
        vm.startPrank(curator);
        vault.submit(abi.encodeCall(IVaultV2.setPerformanceFee, (performanceFee)));
        vault.submit(abi.encodeCall(IVaultV2.setManagementFee, (managementFee)));
        vm.stopPrank();
        vault.setPerformanceFee(performanceFee);
        vault.setManagementFee(managementFee);
        vm.prank(allocator);
        vic.increaseInterestPerSecond(interestPerSecond);
        vm.warp(vm.getBlockTimestamp() + elapsed);

        // Normal path.
        uint256 interest = interestPerSecond * elapsed;
        uint256 totalAssets = deposit + interest;
        uint256 performanceFeeAssets = interest.mulDivDown(performanceFee, WAD);
        uint256 performanceFeeShares =
            performanceFeeAssets.mulDivDown(vault.totalSupply() + 1, totalAssets + 1 - performanceFeeAssets);
        uint256 managementFeeAssets = (totalAssets * elapsed).mulDivDown(managementFee, WAD);
        uint256 managementFeeShares = managementFeeAssets.mulDivDown(
            vault.totalSupply() + 1 + performanceFeeShares, totalAssets + 1 - managementFeeAssets
        );
        vm.expectEmit();
        emit EventsLib.AccrueInterest(deposit, totalAssets, performanceFeeShares, managementFeeShares);
        vault.accrueInterest();
        assertEq(vault.totalAssets(), totalAssets);
        assertEq(vault.balanceOf(performanceFeeRecipient), performanceFeeShares);
        assertEq(vault.balanceOf(managementFeeRecipient), managementFeeShares);
    }

    function testAccrueInterestTooHigh(
        uint256 deposit,
        uint256 performanceFee,
        uint256 managementFee,
        uint256 interestPerSecond,
        uint256 elapsed
    ) public {
        performanceFee = bound(performanceFee, 0, MAX_PERFORMANCE_FEE);
        managementFee = bound(managementFee, 0, MAX_MANAGEMENT_FEE);
        deposit = bound(deposit, 0, MAX_TEST_ASSETS);
        interestPerSecond = bound(interestPerSecond, deposit.mulDivDown(MAX_RATE_PER_SECOND, WAD), type(uint256).max);
        elapsed = bound(elapsed, 0, 20 * 365 days);

        // Setup.
        vault.deposit(deposit, address(this));
        vm.startPrank(curator);
        vault.submit(abi.encodeCall(IVaultV2.setPerformanceFee, (performanceFee)));
        vault.submit(abi.encodeCall(IVaultV2.setManagementFee, (managementFee)));
        vm.stopPrank();
        vault.setPerformanceFee(performanceFee);
        vault.setManagementFee(managementFee);
        vm.warp(vm.getBlockTimestamp() + elapsed);

        // Rate too high.
        vm.prank(allocator);
        vic.increaseInterestPerSecond(interestPerSecond);
        uint256 totalAssetsBefore = vault.totalAssets();
        vault.accrueInterest();
        assertEq(vault.totalAssets(), totalAssetsBefore);
    }

    function testAccrueInterestVicNoCode(uint256 elapsed) public {
        elapsed = bound(elapsed, 0, 1000 weeks);

        // Setup.
        vm.prank(curator);
        vault.submit(abi.encodeCall(IVaultV2.setVic, (address(42))));
        vault.setVic(address(42));
        vm.warp(vm.getBlockTimestamp() + elapsed);

        // Vic reverts.
        uint256 totalAssetsBefore = vault.totalAssets();
        vault.accrueInterest();
        assertEq(vault.totalAssets(), totalAssetsBefore);
    }

    function testAccrueInterestVicReverting(uint256 elapsed) public {
        elapsed = bound(elapsed, 0, 1000 weeks);

        address reverting = address(new Reverting());

        // Setup.
        vm.prank(curator);
        vault.submit(abi.encodeCall(IVaultV2.setVic, (reverting)));
        vault.setVic(reverting);
        vm.warp(vm.getBlockTimestamp() + elapsed);

        // Vic reverts.
        uint256 totalAssetsBefore = vault.totalAssets();
        vault.accrueInterest();
        assertEq(vault.totalAssets(), totalAssetsBefore);
    }

    function testAccrueInterestVicBurnsAllGasNoGates(uint256 elapsed) public {
        elapsed = bound(elapsed, 0, 1000 weeks);

        address burner = address(new BurnsAllGas());

        // Setup.
        vm.startPrank(curator);
        vault.submit(abi.encodeCall(IVaultV2.setVic, (burner)));
        vault.submit(abi.encodeCall(IVaultV2.setPerformanceFeeRecipient, (performanceFeeRecipient)));
        vault.submit(abi.encodeCall(IVaultV2.setManagementFeeRecipient, (managementFeeRecipient)));
        vault.submit(abi.encodeCall(IVaultV2.setPerformanceFee, (MAX_PERFORMANCE_FEE)));
        vault.submit(abi.encodeCall(IVaultV2.setManagementFee, (MAX_MANAGEMENT_FEE)));
        vm.stopPrank();
        vault.setVic(burner);
        vault.setPerformanceFeeRecipient(performanceFeeRecipient);
        vault.setManagementFeeRecipient(managementFeeRecipient);
        vault.setPerformanceFee(MAX_PERFORMANCE_FEE);
        vault.setManagementFee(MAX_MANAGEMENT_FEE);

        vm.warp(vm.getBlockTimestamp() + elapsed);

        // 1/64 * safeGas is enough to accrue interest.
        uint256 safeGas = 1_000_000;
        vault.accrueInterest{gas: safeGas}();
    }

    function testAccrueInterestVicBurnsAllGasWithGates(uint256 elapsed) public {
        elapsed = bound(elapsed, 0, 1000 weeks);

        address burner = address(new BurnsAllGas());
        address gate = address(new Gate());

        // Setup (sort of bad case scenario).
        vm.startPrank(curator);
        vault.submit(abi.encodeCall(IVaultV2.setVic, (burner)));
        vault.submit(abi.encodeCall(IVaultV2.setEnterGate, (gate)));
        vault.submit(abi.encodeCall(IVaultV2.setExitGate, (gate)));
        vault.submit(abi.encodeCall(IVaultV2.setPerformanceFee, (MAX_PERFORMANCE_FEE)));
        vault.submit(abi.encodeCall(IVaultV2.setManagementFee, (MAX_MANAGEMENT_FEE)));
        vm.stopPrank();
        vault.setVic(burner);
        vault.setEnterGate(gate);
        vault.setExitGate(gate);
        vault.setPerformanceFee(MAX_PERFORMANCE_FEE);
        vault.setManagementFee(MAX_MANAGEMENT_FEE);

        vm.warp(vm.getBlockTimestamp() + elapsed);

        // 1/64 * safeGas is enough to accrue interest.
        uint256 safeGas = 10_000_000;
        vault.accrueInterest{gas: safeGas}();
    }

    function testPerformanceFeeWithoutManagementFee(
        uint256 performanceFee,
        uint256 interestPerSecond,
        uint256 deposit,
        uint256 elapsed
    ) public {
        performanceFee = bound(performanceFee, 0, MAX_PERFORMANCE_FEE);
        deposit = bound(deposit, 0, MAX_TEST_ASSETS);
        interestPerSecond = bound(interestPerSecond, 0, deposit.mulDivDown(MAX_RATE_PER_SECOND, WAD));
        elapsed = bound(elapsed, 0, 20 * 365 days);

        vm.prank(curator);
        vault.submit(abi.encodeCall(IVaultV2.setPerformanceFee, (performanceFee)));
        vault.setPerformanceFee(performanceFee);

        vault.deposit(deposit, address(this));

        vm.prank(allocator);
        vic.increaseInterestPerSecond(interestPerSecond);

        vm.warp(block.timestamp + elapsed);

        uint256 interest = interestPerSecond * elapsed;
        uint256 newTotalAssets = vault.totalAssets() + interest;
        uint256 performanceFeeAssets = interest.mulDivDown(performanceFee, WAD);
        uint256 expectedShares =
            performanceFeeAssets.mulDivDown(vault.totalSupply() + 1, newTotalAssets + 1 - performanceFeeAssets);

        vault.accrueInterest();

        assertEq(vault.balanceOf(performanceFeeRecipient), expectedShares);
    }

    function testManagementFeeWithoutPerformanceFee(
        uint256 managementFee,
        uint256 interestPerSecond,
        uint256 deposit,
        uint256 elapsed
    ) public {
        managementFee = bound(managementFee, 0, MAX_MANAGEMENT_FEE);
        deposit = bound(deposit, 0, MAX_TEST_ASSETS);
        interestPerSecond = bound(interestPerSecond, 0, deposit.mulDivDown(MAX_RATE_PER_SECOND, WAD));
        elapsed = bound(elapsed, 0, 20 * 365 days);

        vm.prank(curator);
        vault.submit(abi.encodeCall(IVaultV2.setManagementFee, (managementFee)));
        vault.setManagementFee(managementFee);

        vault.deposit(deposit, address(this));

        vm.prank(allocator);
        vic.increaseInterestPerSecond(interestPerSecond);

        vm.warp(block.timestamp + elapsed);

        uint256 interest = interestPerSecond * elapsed;
        uint256 newTotalAssets = vault.totalAssets() + interest;
        uint256 managementFeeAssets = (newTotalAssets * elapsed).mulDivDown(managementFee, WAD);
        uint256 expectedShares =
            managementFeeAssets.mulDivDown(vault.totalSupply() + 1, newTotalAssets + 1 - managementFeeAssets);

        vault.accrueInterest();

        assertEq(vault.balanceOf(managementFeeRecipient), expectedShares);
    }
}

contract Reverting {}
