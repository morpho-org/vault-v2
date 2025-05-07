// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import "./BaseTest.sol";

contract Adapter is IAdapter {
    constructor(address _underlyingToken, address _vault) {
        IERC20(_underlyingToken).approve(_vault, type(uint256).max);
    }

    function allocateIn(bytes memory data, uint256 assets) external returns (bytes32[] memory ids) {}

    function allocateOut(bytes memory data, uint256 assets) external returns (bytes32[] memory ids) {}
}

contract ForceReallocateTest is BaseTest {
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

    function testForceReallocate(uint256 supplied, uint256 reallocated, uint256 forceReallocatePenalty) public {
        supplied = bound(supplied, 0, MAX_TEST_ASSETS);
        reallocated = bound(reallocated, 0, supplied);
        forceReallocatePenalty = bound(forceReallocatePenalty, 0, MAX_FORCE_REALLOCATE_TO_IDLE_PENALTY);

        vm.prank(curator);
        vault.submit(abi.encodeWithSelector(IVaultV2.setIsAdapter.selector, adapter, true));

        vault.setIsAdapter(adapter, true);

        uint256 shares = vault.deposit(supplied, address(this));
        assertEq(underlyingToken.balanceOf(address(vault)), supplied);

        vm.prank(allocator);
        vault.reallocateFromIdle(address(adapter), hex"", supplied);
        assertEq(underlyingToken.balanceOf(adapter), supplied);

        vm.prank(curator);
        vault.submit(abi.encodeWithSelector(IVaultV2.setForceReallocateToIdlePenalty.selector, forceReallocatePenalty));
        vault.setForceReallocateToIdlePenalty(forceReallocatePenalty);

        uint256 expectedShares = shares - vault.previewWithdraw(reallocated.mulDivDown(forceReallocatePenalty, WAD));
        vm.expectEmit();
        emit EventsLib.ForceReallocateToIdle(address(this), address(this), reallocated);
        uint256 withdrawnShares =
            vault.forceReallocateToIdle(_list(address(adapter)), _list(hex""), _list(reallocated), address(this));
        assertEq(shares - expectedShares, withdrawnShares);
        assertEq(underlyingToken.balanceOf(adapter), supplied - reallocated);
        assertEq(underlyingToken.balanceOf(address(vault)), reallocated);
        assertEq(vault.balanceOf(address(this)), expectedShares);

        vault.withdraw(min(reallocated, vault.previewRedeem(expectedShares)), address(this), address(this));
    }

    function testForceReallocateInvalidInputLength(
        address[] memory adapters,
        bytes[] memory data,
        uint256[] memory assets
    ) public {
        vm.assume(adapters.length != data.length || adapters.length != assets.length);
        vm.expectRevert(ErrorsLib.InvalidInputLength.selector);
        vault.forceReallocateToIdle(adapters, data, assets, address(this));
    }
}
