// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import "forge-std/Test.sol";
import "src/VaultV2.sol";
import "src/interfaces/IAdapter.sol";
import "src/interfaces/IERC20.sol";
import "src/libraries/ErrorsLib.sol";

contract MockERC20 {
    string public name;
    string public symbol;
    uint8 public immutable decimals;
    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

    constructor(string memory _name, string memory _symbol, uint8 _decimals) {
        name = _name;
        symbol = _symbol;
        decimals = _decimals;
    }

    function mint(address to, uint256 amount) external {
        balanceOf[to] += amount;
    }

    function approve(address spender, uint256 amount) external returns (bool) {
        allowance[msg.sender][spender] = amount;
        return true;
    }

    function transfer(address to, uint256 amount) external returns (bool) {
        balanceOf[msg.sender] -= amount;
        balanceOf[to] += amount;
        return true;
    }

    function transferFrom(address from, address to, uint256 amount) external returns (bool) {
        uint256 allowed = allowance[from][msg.sender];
        if (allowed != type(uint256).max) allowance[from][msg.sender] = allowed - amount;
        balanceOf[from] -= amount;
        balanceOf[to] += amount;
        return true;
    }
}

contract MockAdapter is IAdapter {
    IERC20 public immutable asset;
    VaultV2 public immutable vault;
    uint256 public storedAssets;

    constructor(IERC20 _asset, VaultV2 _vault) {
        asset = _asset;
        vault = _vault;
    }

    function allocate(bytes memory data, uint256 assets, bytes4, address)
        external
        returns (bytes32[] memory ids, int256 change)
    {
        require(msg.sender == address(vault), "not vault");
        storedAssets += assets;
        ids = new bytes32[](1);
        ids[0] = keccak256(data);
        change = int256(assets);
    }

    function deallocate(bytes memory data, uint256 assets, bytes4, address)
        external
        returns (bytes32[] memory ids, int256 change)
    {
        require(msg.sender == address(vault), "not vault");
        storedAssets -= assets;
        asset.approve(address(vault), assets);
        ids = new bytes32[](1);
        ids[0] = keccak256(data);
        change = -int256(assets);
    }

    function realAssets() external view returns (uint256 assets) {
        return storedAssets;
    }
}

/// @notice Regression test: forceDeallocate must require allocator/sentinel when penalty is 0
contract ForceDeallocateAccessTest is Test {
    VaultV2 internal vault;
    MockERC20 internal asset;
    MockAdapter internal adapter;

    address internal owner = address(this);
    address internal allocator = address(0xA11CE);
    address internal attacker = address(0xBEEF);

    bytes internal idData = abi.encode("MARKET");

    function setUp() public {
        asset = new MockERC20("Mock", "MOCK", 18);
        vault = new VaultV2(owner, address(asset));

        vault.setCurator(owner);

        bytes memory data = abi.encodeWithSelector(vault.setIsAllocator.selector, allocator, true);
        vault.submit(data);
        vault.setIsAllocator(allocator, true);

        adapter = new MockAdapter(IERC20(address(asset)), vault);
        data = abi.encodeWithSelector(vault.addAdapter.selector, address(adapter));
        vault.submit(data);
        vault.addAdapter(address(adapter));

        data = abi.encodeWithSelector(vault.increaseAbsoluteCap.selector, idData, 1_000 ether);
        vault.submit(data);
        vault.increaseAbsoluteCap(idData, 1_000 ether);

        data = abi.encodeWithSelector(vault.increaseRelativeCap.selector, idData, 1e18);
        vault.submit(data);
        vault.increaseRelativeCap(idData, 1e18);

        asset.mint(address(this), 1_000 ether);
        asset.approve(address(vault), type(uint256).max);
        vault.deposit(1_000 ether, address(this));

        vm.prank(allocator);
        vault.allocate(address(adapter), idData, 500 ether);
        assertEq(adapter.storedAssets(), 500 ether);
    }

    function test_forceDeallocate_reverts_for_attacker_when_penalty_zero() public {
        vm.prank(attacker);
        vm.expectRevert(ErrorsLib.Unauthorized.selector);
        vault.forceDeallocate(address(adapter), idData, 100 ether, attacker);

        assertEq(adapter.storedAssets(), 500 ether);
    }

    function test_forceDeallocate_succeeds_for_allocator_when_penalty_zero() public {
        vm.prank(allocator);
        vault.forceDeallocate(address(adapter), idData, 100 ether, allocator);

        assertEq(adapter.storedAssets(), 400 ether);
    }
}
