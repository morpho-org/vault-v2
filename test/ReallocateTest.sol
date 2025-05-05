// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import "./BaseTest.sol";
import {EventsLib} from "../src/libraries/EventsLib.sol";
import {ErrorsLib} from "../src/libraries/ErrorsLib.sol";
import {MathLib} from "../src/libraries/MathLib.sol";

contract MockAdapter is IAdapter {
    address public immutable vault;
    bytes public recordedData;
    uint256 public recordedAmount;

    constructor(address _vault) {
        vault = _vault;
        IERC20(IVaultV2(_vault).asset()).approve(_vault, type(uint256).max);
    }

    function allocateIn(bytes memory data, uint256 amount) external returns (bytes32[] memory ids) {
        recordedData = data;
        recordedAmount = amount;
        bytes32[] memory _ids = new bytes32[](2);
        _ids[0] = keccak256("id-0");
        _ids[1] = keccak256("id-1");
        return _ids;
    }

    function allocateOut(bytes memory data, uint256 amount) external returns (bytes32[] memory ids) {
        recordedData = data;
        recordedAmount = amount;
        bytes32[] memory _ids = new bytes32[](2);
        _ids[0] = keccak256("id-0");
        _ids[1] = keccak256("id-1");
        return _ids;
    }

    function realiseLoss(bytes memory data) external returns (uint256, bytes32[] memory ids) {}
}

contract ReallocateTest is BaseTest {
    using MathLib for uint256;

    address mockAdapter;
    bytes32[] public ids;

    function setUp() public override {
        super.setUp();

        mockAdapter = address(new MockAdapter(address(vault)));

        deal(address(underlyingToken), address(this), type(uint256).max);
        underlyingToken.approve(address(vault), type(uint256).max);

        vm.prank(curator);
        vault.submit(abi.encodeWithSelector(IVaultV2.setIsAdapter.selector, mockAdapter, true));
        vault.setIsAdapter(mockAdapter, true);

        ids = new bytes32[](2);
        ids[0] = keccak256("id-0");
        ids[1] = keccak256("id-1");
    }

    function _boundAmount(uint256 amount) internal pure returns (uint256) {
        return bound(amount, 1, type(uint256).max);
    }

    function _setAbsoluteCap(bytes memory idData, uint256 absoluteCap) internal {
        bytes32 id = keccak256(idData);
        if (absoluteCap > vault.absoluteCap(id)) {
            vm.prank(curator);
            vault.submit(abi.encodeWithSelector(IVaultV2.increaseAbsoluteCap.selector, idData, absoluteCap));
            vault.increaseAbsoluteCap(idData, absoluteCap);
        } else {
            vm.prank(curator);
            vault.decreaseAbsoluteCap(id, absoluteCap);
        }
        assertEq(vault.absoluteCap(id), absoluteCap);
    }

    function testReallocateFromIdle(bytes memory data, uint256 amount, address rdm, uint256 absoluteCap) public {
        vm.assume(rdm != address(allocator));
        vm.assume(rdm != address(vault));
        amount = _boundAmount(amount);
        absoluteCap = bound(absoluteCap, amount, type(uint256).max);

        // Setup.
        deal(address(underlyingToken), address(vault), amount);
        assertEq(underlyingToken.balanceOf(address(vault)), amount, "Initial vault balance incorrect");
        assertEq(underlyingToken.balanceOf(mockAdapter), 0, "Initial adapter balance incorrect");
        assertEq(vault.allocation(keccak256("id-0")), 0, "Initial allocation incorrect");
        assertEq(vault.allocation(keccak256("id-1")), 0, "Initial allocation incorrect");

        // Access control.
        vm.prank(rdm);
        vm.expectRevert(ErrorsLib.NotAllocator.selector);
        vault.reallocateFromIdle(mockAdapter, data, amount);
        vm.prank(address(vault));
        vault.reallocateFromIdle(mockAdapter, hex"", 0);
        vm.prank(allocator);
        vault.reallocateFromIdle(mockAdapter, hex"", 0);

        // Can't reallocate from idle if not adapter.
        vm.prank(allocator);
        vm.expectRevert(ErrorsLib.NotAdapter.selector);
        vault.reallocateFromIdle(address(this), hex"", 0);

        // Absolute cap check.
        _setAbsoluteCap("id-0", amount - 1);
        _setAbsoluteCap("id-1", amount - 1);
        vm.expectRevert(ErrorsLib.AbsoluteCapExceeded.selector);
        vm.prank(allocator);
        vault.reallocateFromIdle(mockAdapter, data, amount);

        // Normal path.
        _setAbsoluteCap("id-0", amount);
        _setAbsoluteCap("id-1", amount);
        vm.prank(allocator);
        vm.expectEmit();
        emit EventsLib.ReallocateFromIdle(allocator, mockAdapter, amount, ids);
        vault.reallocateFromIdle(mockAdapter, data, amount);
        assertEq(underlyingToken.balanceOf(address(vault)), 0, "Vault balance should be zero after reallocation");
        assertEq(underlyingToken.balanceOf(mockAdapter), amount, "Adapter balance incorrect after reallocation");
        assertEq(vault.allocation(keccak256("id-0")), amount, "Allocation incorrect after reallocation");
        assertEq(vault.allocation(keccak256("id-1")), amount, "Allocation incorrect after reallocation");
        assertEq(MockAdapter(mockAdapter).recordedData(), data, "Data incorrect after reallocation");
        assertEq(MockAdapter(mockAdapter).recordedAmount(), amount, "Amount incorrect after reallocation");
    }

    function testReallocateToIdle(
        bytes memory data,
        uint256 amountIn,
        uint256 amountOut,
        address rdm,
        uint256 absoluteCap
    ) public {
        vm.assume(rdm != address(allocator));
        vm.assume(rdm != address(sentinel));
        vm.assume(rdm != address(vault));
        amountIn = _boundAmount(amountIn);
        amountOut = bound(amountOut, 1, amountIn);
        absoluteCap = bound(absoluteCap, amountIn, type(uint256).max);

        // Setup.
        deal(address(underlyingToken), address(vault), amountIn);
        _setAbsoluteCap("id-0", amountIn);
        _setAbsoluteCap("id-1", amountIn);
        vm.prank(allocator);
        vault.reallocateFromIdle(mockAdapter, data, amountIn);

        // Access control.
        vm.prank(rdm);
        vm.expectRevert(ErrorsLib.NotAllocator.selector);
        vault.reallocateToIdle(mockAdapter, hex"", 0);
        vm.prank(allocator);
        vault.reallocateToIdle(mockAdapter, hex"", 0);
        vm.prank(sentinel);
        vault.reallocateToIdle(mockAdapter, hex"", 0);
        vm.prank(address(vault));
        vault.reallocateToIdle(mockAdapter, hex"", 0);

        // Can't reallocate to idle if not adapter.
        vm.prank(allocator);
        vm.expectRevert(ErrorsLib.NotAdapter.selector);
        vault.reallocateToIdle(address(this), data, amountOut);

        // Normal path.
        _setAbsoluteCap("id-0", amountIn);
        _setAbsoluteCap("id-1", amountIn);
        vm.prank(allocator);
        vm.expectEmit();
        emit EventsLib.ReallocateToIdle(allocator, mockAdapter, amountOut, ids);
        vault.reallocateToIdle(mockAdapter, data, amountOut);
        assertEq(underlyingToken.balanceOf(address(vault)), amountOut, "Vault balance incorrect after reallocation");
        assertEq(
            underlyingToken.balanceOf(mockAdapter), amountIn - amountOut, "Adapter balance incorrect after reallocation"
        );
        assertEq(vault.allocation(keccak256("id-0")), amountIn - amountOut, "Allocation incorrect after reallocation");
        assertEq(vault.allocation(keccak256("id-1")), amountIn - amountOut, "Allocation incorrect after reallocation");
        assertEq(MockAdapter(mockAdapter).recordedData(), data, "Data incorrect after reallocation");
        assertEq(MockAdapter(mockAdapter).recordedAmount(), amountOut, "Amount incorrect after reallocation");
    }
}
