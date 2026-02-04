// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "forge-std/Test.sol";
import "src/VaultV2.sol";
import "src/libraries/ErrorsLib.sol";

contract SimpleERC20 {
    string public name = "TestToken";
    string public symbol = "TT";
    uint8 public decimals = 18;
    uint256 public totalSupply;
    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

    constructor() {
        _mint(msg.sender, 1e24);
    }

    function _mint(address to, uint256 amount) internal {
        totalSupply += amount;
        balanceOf[to] += amount;
        emit Transfer(address(0), to, amount);
    }

    function transfer(address to, uint256 amount) external returns (bool) {
        balanceOf[msg.sender] -= amount;
        balanceOf[to] += amount;
        emit Transfer(msg.sender, to, amount);
        return true;
    }

    function approve(address spender, uint256 amount) external returns (bool) {
        allowance[msg.sender][spender] = amount;
        emit Approval(msg.sender, spender, amount);
        return true;
    }

    function transferFrom(address from, address to, uint256 amount) external returns (bool) {
        uint256 allowed = allowance[from][msg.sender];
        if (allowed != type(uint256).max) {
            allowance[from][msg.sender] = allowed - amount;
        }
        balanceOf[from] -= amount;
        balanceOf[to] += amount;
        emit Transfer(from, to, amount);
        return true;
    }

    event Transfer(address indexed from, address indexed to, uint256 amount);
    event Approval(address indexed owner, address indexed spender, uint256 amount);
}

/// @notice Regression test: cannot remove curator/sentinel when pending actions exist
contract RevokeLivenessTest is Test {
    VaultV2 vault;
    SimpleERC20 token;
    address owner = address(this);
    address curator = address(0xBEEF);

    function setUp() public {
        token = new SimpleERC20();
        vault = new VaultV2(owner, address(token));
        vault.setCurator(curator);
    }

    function test_cannot_set_curator_to_zero_with_pending_actions() public {
        bytes memory data = abi.encodeWithSelector(vault.setIsAllocator.selector, address(0x1234), true);

        vm.prank(curator);
        vault.submit(data);
        uint256 exec = vault.executableAt(data);
        assertGt(exec, 0, "executableAt should be set");

        vm.expectRevert(ErrorsLib.NoRevoker.selector);
        vault.setCurator(address(0));
    }

    function test_can_set_curator_to_zero_with_sentinel() public {
        vault.setIsSentinel(address(0xCAFE), true);

        bytes memory data = abi.encodeWithSelector(vault.setIsAllocator.selector, address(0x1234), true);

        vm.prank(curator);
        vault.submit(data);

        vault.setCurator(address(0));
        assertEq(vault.curator(), address(0));

        vm.prank(address(0xCAFE));
        vault.revoke(data);

        assertEq(vault.executableAt(data), 0);
    }

    function test_cannot_remove_last_sentinel_with_pending_actions_and_no_curator() public {
        vault.setIsSentinel(address(0xCAFE), true);

        bytes memory data = abi.encodeWithSelector(vault.setIsAllocator.selector, address(0x1234), true);

        vm.prank(curator);
        vault.submit(data);

        vault.setCurator(address(0));

        vm.expectRevert(ErrorsLib.NoRevoker.selector);
        vault.setIsSentinel(address(0xCAFE), false);
    }
}
