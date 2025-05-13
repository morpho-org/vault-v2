// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import "./BaseTest.sol";

contract BasicAdapter is IAdapter {
    constructor(address _underlyingToken, address _vault) {
        IERC20(_underlyingToken).approve(_vault, type(uint256).max);
    }

    function allocate(bytes memory idData, uint256) external pure returns (bytes32[] memory) {
        bytes32[] memory ids = new bytes32[](1);
        ids[0] = keccak256(idData);
        return ids;
    }

    function deallocate(bytes memory data, uint256 assets) external returns (bytes32[] memory ids) {}
}

contract RelativeCapsTest is BaseTest {
    using MathLib for uint256;

    uint256 constant MAX_TEST_ASSETS = 1e36;
    address adapter;

    function setUp() public override {
        super.setUp();

        adapter = address(new BasicAdapter(address(underlyingToken), address(vault)));

        deal(address(underlyingToken), address(this), type(uint256).max);
        underlyingToken.approve(address(vault), type(uint256).max);
    }

    function _setUpRelativeCap(bytes memory idData, uint256 cap) internal {
        vm.prank(curator);
        vault.submit(abi.encodeWithSelector(IVaultV2.increaseAbsoluteCap.selector, idData, type(uint256).max));
        vault.increaseAbsoluteCap(idData, type(uint256).max);
        vm.prank(curator);
        vault.submit(abi.encodeWithSelector(IVaultV2.decreaseRelativeCap.selector, idData, cap));
        vault.decreaseRelativeCap(idData, cap);
        vm.prank(curator);
        vault.submit(abi.encodeWithSelector(IVaultV2.setIsAdapter.selector, adapter, true));
        vault.setIsAdapter(adapter, true);
    }

    function test_relativeCapExceededOnAllocate(uint256 cap, uint256 alloc) public {
        cap = bound(cap, 1, WAD - 1);
        alloc = bound(alloc, 1, MAX_TEST_ASSETS);
        uint256 total = alloc * WAD / cap;
        bytes memory idData = "id";

        _setUpRelativeCap(idData, cap);

        vault.deposit(total, address(this));
        vm.prank(allocator);
        vm.expectRevert(ErrorsLib.RelativeCapExceeded.selector);
        vault.allocate(adapter, idData, alloc);
    }

    function test_relativeCapExceededOnDecreaseRelativeCap(uint256 cap, uint256 alloc, uint256 newCap) public {
        cap = bound(cap, 100, WAD - 1);
        alloc = bound(alloc, 1, cap * 0.95e18 / WAD);
        newCap = bound(newCap, 1, alloc);
        bytes memory idData = "id";

        _setUpRelativeCap(idData, cap);

        vault.deposit(WAD, address(this));
        vm.prank(allocator);
        vault.allocate(adapter, idData, alloc);

        vm.prank(curator);
        vault.submit(abi.encodeWithSelector(IVaultV2.decreaseRelativeCap.selector, idData, newCap));
        vm.expectRevert(ErrorsLib.RelativeCapExceeded.selector);
        vault.decreaseRelativeCap(idData, newCap);
    }

    function test_relativeCapExceededOnExit(uint256 cap, uint256 alloc) public {
        cap = bound(cap, 100, WAD - 1);
        alloc = bound(alloc, 1, cap * 0.95e18 / WAD);
        bytes memory idData = "id";

        _setUpRelativeCap(idData, cap);

        vault.deposit(WAD, address(this));
        vm.prank(allocator);
        vault.allocate(adapter, idData, alloc);

        vm.expectRevert(ErrorsLib.RelativeCapExceeded.selector);
        vault.withdraw(WAD - alloc, address(this), address(this));
    }
}
