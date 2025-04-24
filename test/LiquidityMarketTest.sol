// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.28;

import "./BaseTest.sol";

contract RecordingAdapter {
    bytes public recordedData;
    uint256 public recordedAmount;

    function allocateIn(bytes memory data, uint256 amount) external returns (bytes32[] memory ids) {
        recordedData = data;
        recordedAmount = amount;
        ids = new bytes32[](0);
    }
}

contract LiquidityMarketTest is BaseTest {
    using MathLib for uint256;

    RecordingAdapter public adapter;

    function setUp() public override {
        super.setUp();

        adapter = new RecordingAdapter();

        deal(address(underlyingToken), address(this), type(uint256).max);
        underlyingToken.approve(address(vault), type(uint256).max);
    }

    function testLiquidityMarketDeposit(bytes memory data, uint256 assets) public {
        vm.prank(owner);
        vault.submit(abi.encodeWithSelector(IVaultV2.setIsAdapter.selector, address(adapter), true));
        vault.setIsAdapter(address(adapter), true);

        vm.prank(allocator);
        vault.setLiquidityMarket(address(adapter), data);

        vault.deposit(assets, address(this));

        assertEq(adapter.recordedData(), data);
        assertEq(adapter.recordedAmount(), assets);
    }

    function testLiquidityMarketMint(bytes memory data, uint256 shares) public {
        vm.prank(owner);
        vault.submit(abi.encodeWithSelector(IVaultV2.setIsAdapter.selector, address(adapter), true));
        vault.setIsAdapter(address(adapter), true);

        vm.prank(allocator);
        vault.setLiquidityMarket(address(adapter), data);

        uint256 assets = shares.mulDivDown(vault.totalAssets() + 1, vault.totalSupply() + 1);

        vault.mint(shares, address(this));

        assertEq(adapter.recordedData(), data);
        assertEq(adapter.recordedAmount(), assets);
    }
}
