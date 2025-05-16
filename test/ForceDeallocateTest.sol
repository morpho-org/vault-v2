// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import "./BaseTest.sol";

contract Adapter is IAdapter {
    constructor(address _underlyingToken, address _vault) {
        IERC20(_underlyingToken).approve(_vault, type(uint256).max);
    }

    function allocate(bytes memory data, uint256 assets) external returns (bytes32[] memory ids) {}

    function deallocate(bytes memory data, uint256 assets) external returns (bytes32[] memory ids) {}
}

contract ForceDeallocateTest is BaseTest {
    using MathLib for uint256;

    uint256 constant MAX_TEST_ASSETS = 1e36;
    address adapter;

    function setUp() public override {
        super.setUp();

        adapter = address(new Adapter(address(underlyingToken), address(vault)));

        deal(address(underlyingToken), address(this), type(uint256).max);
        underlyingToken.approve(address(vault), type(uint256).max);
    }

    function _list(address input) internal pure returns (address[] memory) {
        address[] memory list = new address[](1);
        list[0] = input;
        return list;
    }

    function _list(bytes memory input) internal pure returns (bytes[] memory) {
        bytes[] memory list = new bytes[](1);
        list[0] = input;
        return list;
    }

    function _list(uint256 input) internal pure returns (uint256[] memory) {
        uint256[] memory list = new uint256[](1);
        list[0] = input;
        return list;
    }

    function testForceDeallocate(uint256 supplied, uint256 deallocated, uint256 forceDeallocatePenalty) public {
        supplied = bound(supplied, 0, MAX_TEST_ASSETS);
        deallocated = bound(deallocated, 0, supplied);
        forceDeallocatePenalty = bound(forceDeallocatePenalty, 0, MAX_FORCE_DEALLOCATE_PENALTY);

        vm.prank(curator);
        vault.submit(abi.encodeCall(IVaultV2.setIsAdapter, (adapter, true)));

        vault.setIsAdapter(adapter, true);

        uint256 shares = vault.deposit(supplied, address(this));
        assertEq(underlyingToken.balanceOf(address(vault)), supplied);

        vm.prank(allocator);
        vault.allocate(address(adapter), hex"", supplied);
        assertEq(underlyingToken.balanceOf(adapter), supplied);

        vm.prank(curator);
        vault.submit(abi.encodeCall(IVaultV2.setForceDeallocatePenalty, (adapter, forceDeallocatePenalty)));
        vault.setForceDeallocatePenalty(adapter, forceDeallocatePenalty);

        uint256 penaltyAssets = deallocated.mulDivDown(forceDeallocatePenalty, WAD);
        uint256 expectedShares = shares - vault.previewWithdraw(penaltyAssets);
        address[] memory adapters = _list(address(adapter));
        bytes[] memory data = _list(hex"");
        uint256[] memory assets = _list(deallocated);
        vm.expectEmit();
        emit EventsLib.ForceDeallocate(address(this), adapters, data, assets, address(this));
        uint256 withdrawnShares = vault.forceDeallocate(adapters, data, assets, address(this));
        assertEq(shares - expectedShares, withdrawnShares);
        assertEq(underlyingToken.balanceOf(adapter), supplied - deallocated);
        assertEq(underlyingToken.balanceOf(address(vault)), deallocated);
        assertEq(vault.balanceOf(address(this)), expectedShares);

        vault.withdraw(min(deallocated, vault.previewRedeem(expectedShares)), address(this), address(this));
    }

    function testForceDeallocateInvalidInputLength(
        address[] memory adapters,
        bytes[] memory data,
        uint256[] memory assets
    ) public {
        vm.assume(adapters.length != data.length || adapters.length != assets.length);
        vm.expectRevert(ErrorsLib.InvalidInputLength.selector);
        vault.forceDeallocate(adapters, data, assets, address(this));
    }
}
