// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import "./BaseTest.sol";

contract Reverting {}

// Burn almost all gas and return toReturn.
contract BurnsAllGas {
    uint256 immutable returnValue;

    constructor(uint256 _returnValue) {
        returnValue = _returnValue;
    }

    fallback() external {
        // gasToMemoryExpansion uses 1021 gas. Update if needed.
        // Reserving 50 gas for the return subtraction and the return.
        uint256 burnAmount = gasleft() - 1021 - 50;
        uint256 words = gasToMemoryExpansion(burnAmount);
        uint256 _returnValue = returnValue;

        assembly ("memory-safe") {
            mstore(mul(sub(words, 1), 32), 1)
            mstore(0, _returnValue)
            return(0, 32)
        }
    }
}

// Burn an approximate amount of gas and return 1.
contract BurnsGas {
    uint256 immutable burnAmount;
    BurnsAllGas immutable burner;

    constructor(uint256 _burnAmount) {
        burnAmount = _burnAmount;
        burner = new BurnsAllGas(0);
    }

    fallback() external {
        (bool s, bytes memory r) = address(burner).call{gas: 64 * burnAmount / 63}("");
        // No-op to silence warning.
        s;
        r;
        // return 1
        assembly ("memory-safe") {
            mstore(0, 1)
            return(0, 32)
        }
    }
}

contract ReturnsBomb {
    fallback() external {
        // expansion cost: 3 * words + floor(words**2/512) = 4953
        uint256 words = 1e3;
        assembly {
            mstore(mul(sub(words, 1), 32), 1)
            return(0, mul(words, 32))
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

    uint256 constant GAS_BURNED_BY_GATE = 1_000_000;
    uint256 constant SAFE_GAS_AMOUNT = 2_000_000;

    function testGasRequiredToAccrueIfVicBurnsAllGas() public {
        // Vault setup
        deal(address(underlyingToken), address(this), 1e18);
        underlyingToken.approve(address(vault), type(uint256).max);

        vm.startPrank(curator);

        uint256 amount = 1e18;
        uint256 interestPerSecond = amount * MAX_RATE_PER_SECOND / WAD;

        // make accrueInterest as costly as possible
        // but keep gates cost reasonable since the gate can be changed without accruing interest
        // rationale is that it is OK for a shares gate to lock users anyway
        address gate = address(new BurnsGas(GAS_BURNED_BY_GATE));
        vault.submit(abi.encodeCall(vault.setSharesGate, (gate)));
        vault.setSharesGate(gate);

        performanceFeeRecipient = makeAddr("performance fee recipient");
        vault.submit(abi.encodeCall(vault.setPerformanceFeeRecipient, (performanceFeeRecipient)));
        vault.setPerformanceFeeRecipient(performanceFeeRecipient);

        managementFeeRecipient = makeAddr("management fee recipient");
        vault.submit(abi.encodeCall(vault.setManagementFeeRecipient, (managementFeeRecipient)));
        vault.setManagementFeeRecipient(managementFeeRecipient);

        vault.submit(abi.encodeCall(vault.setPerformanceFee, (MAX_PERFORMANCE_FEE)));
        vault.setPerformanceFee(MAX_PERFORMANCE_FEE);

        vault.submit(abi.encodeCall(vault.setManagementFee, (MAX_MANAGEMENT_FEE)));
        vault.setManagementFee(MAX_MANAGEMENT_FEE);

        vm.stopPrank();

        vault.deposit(amount, address(this));

        BurnsAllGas burnsAllGas = new BurnsAllGas(interestPerSecond);
        vm.prank(curator);
        vault.submit(abi.encodeCall(vault.setVic, (address(burnsAllGas))));
        vault.setVic(address(burnsAllGas));

        skip(2 weeks);

        vault.accrueInterest{gas: SAFE_GAS_AMOUNT + 2 * GAS_BURNED_BY_GATE}();

        // check that gas was almost entirely burned
        assertGt(vm.lastCallGas().gasTotalUsed, SAFE_GAS_AMOUNT * 63 / 64);
    }

    function testReturnsBombCaught(bytes calldata) public {
        address newVic = address(new ReturnsBomb());

        uint256 gas = 4953 * 2;
        try this._staticcall{gas: gas}(newVic) {} catch {}
    }

    function testReturnsBombNotCaught(bytes calldata) public {
        address newVic = address(new ReturnsBomb());

        uint256 gas = 4953 * 2;
        vm.expectRevert();
        this._staticcall{gas: gas}(newVic);
    }

    function _staticcall(address account) external view {
        (bool success,) = account.staticcall(hex"");
        success; // No-op to silence warning.
    }
}

/* FREE UTILITY FUNCTIONS */

// approximate the inverse of the memory expansion cost function
// cost function is g(w) = 3w + ⌊w²/512⌋.
// approximated to w(g) = [ sqrt(1536² + 4 * 512 * g) - 1536 ] / 2.
function gasToMemoryExpansion(uint256 gas) pure returns (uint256) {
    return (sqrt(1536 * 1536 + 4 * 512 * gas) - 1536) / 2;
}

// From
// https://github.com/Vectorized/solady/blob/b609a9c79ce541c2beca7a7d247665e7c93942a3/src/utils/FixedPointMathLib.sol
// Stripped comments
/// @dev Returns the square root of `x`, rounded down.
function sqrt(uint256 x) pure returns (uint256 z) {
    assembly ("memory-safe") {
        z := 181

        let r := shl(7, lt(0xffffffffffffffffffffffffffffffffff, x))
        r := or(r, shl(6, lt(0xffffffffffffffffff, shr(r, x))))
        r := or(r, shl(5, lt(0xffffffffff, shr(r, x))))
        r := or(r, shl(4, lt(0xffffff, shr(r, x))))
        z := shl(shr(1, r), z)

        z := shr(18, mul(z, add(shr(r, x), 65536)))

        z := shr(1, add(z, div(x, z)))
        z := shr(1, add(z, div(x, z)))
        z := shr(1, add(z, div(x, z)))
        z := shr(1, add(z, div(x, z)))
        z := shr(1, add(z, div(x, z)))
        z := shr(1, add(z, div(x, z)))
        z := shr(1, add(z, div(x, z)))

        z := sub(z, lt(div(x, z), z))
    }
}
