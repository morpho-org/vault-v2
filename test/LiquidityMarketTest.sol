// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.28;

import "./BaseTest.sol";

contract LiquidityMarketTest is BaseTest {
    using MathLib for uint256;

    bytes recodedData;
    uint256 recodedAmount;

    function setUp() public override {
        super.setUp();

        deal(address(underlyingToken), address(this), type(uint256).max);
        underlyingToken.approve(address(vault), type(uint256).max);
    }

    function testLiquidityMarketDeposit(bytes memory data, uint256 assets) public {
        vm.prank(owner);
        vault.submit(abi.encodeWithSelector(IVaultV2.setIsAdapter.selector, address(this), true));
        vault.setIsAdapter(address(this), true);

        vm.prank(allocator);
        vault.submit(abi.encodeWithSelector(IVaultV2.setLiquidityMarket.selector, address(this), data));
        vault.setLiquidityMarket(address(this), data);

        vault.deposit(assets, address(this));

        assertEq(recodedData, data);
        assertEq(recodedAmount, assets);
    }

    function testLiquidityMarketMint(bytes memory data, uint256 shares) public {
        vm.prank(owner);
        vault.submit(abi.encodeWithSelector(IVaultV2.setIsAdapter.selector, address(this), true));
        vault.setIsAdapter(address(this), true);

        vm.prank(allocator);
        vault.submit(abi.encodeWithSelector(IVaultV2.setLiquidityMarket.selector, address(this), data));
        vault.setLiquidityMarket(address(this), data);

        uint256 assets = shares.mulDivDown(vault.totalAssets() + 1, vault.totalSupply() + 1);

        vault.mint(shares, address(this));

        assertEq(recodedData, data);
        assertEq(recodedAmount, assets);
    }

    function allocateIn(bytes memory data, uint256 amount) external returns (bytes32[] memory ids) {
        recodedData = data;
        recodedAmount = amount;
        ids = new bytes32[](0);
    }
}
