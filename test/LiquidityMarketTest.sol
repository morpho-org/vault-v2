// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "./BaseTest.sol";

contract RecordingAdapter {
    bytes public recordedData;
    uint256 public recordedAmount;

    function allocateIn(bytes memory data, uint256 amount) external returns (bytes32[] memory ids) {
        recordedData = data;
        recordedAmount = amount;
        ids = new bytes32[](0);
    }

    function allocateOut(bytes memory data, uint256 amount)
        external
        returns (uint256 proportionalCost, bytes32[] memory ids)
    {
        recordedData = data;
        recordedAmount = amount;
        ids = new bytes32[](0);
        proportionalCost = amount;
    }
}

contract LiquidityMarketTest is BaseTest {
    using MathLib for uint256;

    RecordingAdapter public adapter;
    uint256 MAX_DEPOSIT = 1e18 ether;

    function setUp() public override {
        super.setUp();

        adapter = new RecordingAdapter();

        deal(address(underlyingToken), address(this), type(uint256).max);
        underlyingToken.approve(address(vault), type(uint256).max);

        vm.prank(curator);
        vault.submit(abi.encodeWithSelector(IVaultV2.setIsAdapter.selector, address(adapter), true));
        vault.setIsAdapter(address(adapter), true);

        vm.prank(allocator);
        vault.setLiquidityAdapter(address(adapter));

        vm.prank(address(adapter));
        underlyingToken.approve(address(vault), type(uint256).max);
    }

    function testLiquidityMarketDeposit(bytes memory data, uint256 assets) public {
        assets = bound(assets, 0, MAX_DEPOSIT);

        vm.prank(allocator);
        vault.setLiquidityData(data);

        vault.deposit(assets, address(this));

        assertEq(adapter.recordedData(), data);
        assertEq(adapter.recordedAmount(), assets);
    }

    function testLiquidityMarketMint(bytes memory data, uint256 shares) public {
        shares = bound(shares, 0, MAX_DEPOSIT);

        vm.prank(allocator);
        vault.setLiquidityData(data);

        uint256 assets = vault.mint(shares, address(this));

        assertEq(adapter.recordedData(), data);
        assertEq(adapter.recordedAmount(), assets);
    }

    function testLiquidityMarketWithdraw(bytes memory data, uint256 deposit) public {
        deposit = bound(deposit, 0, MAX_DEPOSIT);

        vm.prank(allocator);
        vault.setLiquidityData(data);

        vault.deposit(deposit, address(this));
        uint256 assets = vault.previewRedeem(vault.balanceOf(address(this)));
        vault.withdraw(assets, address(this), address(this));

        assertEq(adapter.recordedData(), data);
        assertEq(adapter.recordedAmount(), assets);
    }

    function testLiquidityMarketRedeem(bytes memory data, uint256 deposit) public {
        deposit = bound(deposit, 0, MAX_DEPOSIT);

        vm.prank(allocator);
        vault.setLiquidityData(data);

        vault.deposit(deposit, address(this));
        uint256 assets = vault.redeem(vault.balanceOf(address(this)), address(this), address(this));

        assertEq(adapter.recordedData(), data);
        assertEq(adapter.recordedAmount(), assets);
    }
}
