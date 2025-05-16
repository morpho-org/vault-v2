// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import "./BaseTest.sol";
import {EventsLib} from "../src/libraries/EventsLib.sol";
import {ErrorsLib} from "../src/libraries/ErrorsLib.sol";
import {MathLib} from "../src/libraries/MathLib.sol";

contract MockAdapter is IAdapter {
    address public immutable vault;
    bytes public recordedData;
    uint256 public recordedAssets;

    constructor(address _vault) {
        vault = _vault;
        IERC20(IVaultV2(_vault).asset()).approve(_vault, type(uint256).max);
    }

    function allocate(bytes memory data, uint256 assets) external returns (bytes32[] memory ids) {
        recordedData = data;
        recordedAssets = assets;
        bytes32[] memory _ids = new bytes32[](2);
        _ids[0] = keccak256("id-0");
        _ids[1] = keccak256("id-1");
        return _ids;
    }

    function deallocate(bytes memory data, uint256 assets) external returns (bytes32[] memory ids) {
        recordedData = data;
        recordedAssets = assets;
        bytes32[] memory _ids = new bytes32[](2);
        _ids[0] = keccak256("id-0");
        _ids[1] = keccak256("id-1");
        return _ids;
    }
}

contract AllocateTest is BaseTest {
    using MathLib for uint256;

    address mockAdapter;
    bytes32[] public ids;

    function setUp() public override {
        super.setUp();

        mockAdapter = address(new MockAdapter(address(vault)));

        deal(address(underlyingToken), address(this), type(uint256).max);
        underlyingToken.approve(address(vault), type(uint256).max);

        vm.prank(curator);
        vault.submit(abi.encodeCall(IVaultV2.setIsAdapter, (mockAdapter, true)));
        vault.setIsAdapter(mockAdapter, true);

        ids = new bytes32[](2);
        ids[0] = keccak256("id-0");
        ids[1] = keccak256("id-1");
    }

    function _boundAssets(uint256 assets) internal pure returns (uint256) {
        return bound(assets, 1, type(uint256).max);
    }

    function _setAbsoluteCap(bytes memory idData, uint256 absoluteCap) internal {
        bytes32 id = keccak256(idData);
        if (absoluteCap > vault.absoluteCap(id)) {
            vm.prank(curator);
            vault.submit(abi.encodeCall(IVaultV2.increaseAbsoluteCap, (idData, absoluteCap)));
            vault.increaseAbsoluteCap(idData, absoluteCap);
        } else {
            vm.prank(curator);
            vault.decreaseAbsoluteCap(idData, absoluteCap);
        }
        assertEq(vault.absoluteCap(id), absoluteCap);
    }

    function testAllocate(bytes memory data, uint256 assets, address rdm, uint256 absoluteCap) public {
        vm.assume(rdm != address(allocator));
        vm.assume(rdm != address(vault));
        assets = _boundAssets(assets);
        absoluteCap = bound(absoluteCap, assets, type(uint256).max);

        // Setup.
        deal(address(underlyingToken), address(vault), assets);
        assertEq(underlyingToken.balanceOf(address(vault)), assets, "Initial vault balance incorrect");
        assertEq(underlyingToken.balanceOf(mockAdapter), 0, "Initial adapter balance incorrect");
        assertEq(vault.allocation(keccak256("id-0")), 0, "Initial allocation incorrect");
        assertEq(vault.allocation(keccak256("id-1")), 0, "Initial allocation incorrect");

        // Access control.
        vm.prank(rdm);
        vm.expectRevert(ErrorsLib.NotAllocator.selector);
        vault.allocate(mockAdapter, data, assets);
        vm.prank(address(vault));
        vault.allocate(mockAdapter, hex"", 0);
        vm.prank(allocator);
        vault.allocate(mockAdapter, hex"", 0);

        // Can't allocate if not adapter.
        vm.prank(allocator);
        vm.expectRevert(ErrorsLib.NotAdapter.selector);
        vault.allocate(address(this), data, assets);

        // Absolute cap check.
        _setAbsoluteCap("id-0", assets - 1);
        _setAbsoluteCap("id-1", assets - 1);
        vm.expectRevert(ErrorsLib.AbsoluteCapExceeded.selector);
        vm.prank(allocator);
        vault.allocate(mockAdapter, data, assets);

        // Normal path.
        _setAbsoluteCap("id-0", assets);
        _setAbsoluteCap("id-1", assets);
        vm.prank(allocator);
        vm.expectEmit();
        emit EventsLib.Allocate(allocator, mockAdapter, assets, ids);
        vault.allocate(mockAdapter, data, assets);
        assertEq(underlyingToken.balanceOf(address(vault)), 0, "Vault balance should be zero after allocation");
        assertEq(underlyingToken.balanceOf(mockAdapter), assets, "Adapter balance incorrect after allocation");
        assertEq(vault.allocation(keccak256("id-0")), assets, "Allocation incorrect after allocation");
        assertEq(vault.allocation(keccak256("id-1")), assets, "Allocation incorrect after allocation");
        assertEq(MockAdapter(mockAdapter).recordedData(), data, "Data incorrect after allocation");
        assertEq(MockAdapter(mockAdapter).recordedAssets(), assets, "Assets incorrect after allocation");
    }

    function testDeallocate(bytes memory data, uint256 assetsIn, uint256 assetsOut, address rdm, uint256 absoluteCap)
        public
    {
        vm.assume(rdm != address(allocator));
        vm.assume(rdm != address(sentinel));
        vm.assume(rdm != address(vault));
        assetsIn = _boundAssets(assetsIn);
        assetsOut = bound(assetsOut, 1, assetsIn);
        absoluteCap = bound(absoluteCap, assetsIn, type(uint256).max);

        // Setup.
        deal(address(underlyingToken), address(vault), assetsIn);
        _setAbsoluteCap("id-0", assetsIn);
        _setAbsoluteCap("id-1", assetsIn);
        vm.prank(allocator);
        vault.allocate(mockAdapter, data, assetsIn);

        // Access control.
        vm.prank(rdm);
        vm.expectRevert(ErrorsLib.NotAllocator.selector);
        vault.deallocate(mockAdapter, hex"", 0);
        vm.prank(allocator);
        vault.deallocate(mockAdapter, hex"", 0);
        vm.prank(sentinel);
        vault.deallocate(mockAdapter, hex"", 0);
        vm.prank(address(vault));
        vault.deallocate(mockAdapter, hex"", 0);

        // Can't deallocate if not adapter.
        vm.prank(allocator);
        vm.expectRevert(ErrorsLib.NotAdapter.selector);
        vault.deallocate(address(this), data, assetsOut);

        // Normal path.
        _setAbsoluteCap("id-0", assetsIn);
        _setAbsoluteCap("id-1", assetsIn);
        vm.prank(allocator);
        vm.expectEmit();
        emit EventsLib.Deallocate(allocator, mockAdapter, assetsOut, ids);
        vault.deallocate(mockAdapter, data, assetsOut);
        assertEq(underlyingToken.balanceOf(address(vault)), assetsOut, "Vault balance incorrect after deallocation");
        assertEq(
            underlyingToken.balanceOf(mockAdapter), assetsIn - assetsOut, "Adapter balance incorrect after deallocation"
        );
        assertEq(vault.allocation(keccak256("id-0")), assetsIn - assetsOut, "Allocation incorrect after deallocation");
        assertEq(vault.allocation(keccak256("id-1")), assetsIn - assetsOut, "Allocation incorrect after deallocation");
        assertEq(MockAdapter(mockAdapter).recordedData(), data, "Data incorrect after deallocation");
        assertEq(MockAdapter(mockAdapter).recordedAssets(), assetsOut, "Assets incorrect after deallocation");
    }
}
