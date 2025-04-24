// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.28;

library EventsLib {
    event Transfer(address indexed from, address indexed to, uint256 amount);
    event Approval(address indexed owner, address indexed spender, uint256 amount);
    event Permit(address indexed owner, address indexed spender, uint256 value, uint256 deadline, uint256 nonce);
    event SetOwner(address indexed newOwner);
    event SetCurator(address indexed newCurator);
    event SetTreasurer(address indexed newTreasurer);
    event SetIRM(address indexed newIRM);
    event SetIsSentinel(address indexed sentinel, bool isSentinel);
    event SetIsAllocator(address indexed allocator, bool isAllocator);
    event SetPerformanceFeeRecipient(address indexed newPerformanceFeeRecipient);
    event SetManagementFeeRecipient(address indexed newManagementFeeRecipient);
    event SetIsAdapter(address indexed adapter, bool isAdapter);
    event IncreaseTimelock(bytes4 indexed selector, uint256 newDuration);
    event DecreaseTimelock(bytes4 indexed selector, uint256 newDuration);
    event SetPerformanceFee(uint256 newPerformanceFee);
    event SetManagementFee(uint256 newManagementFee);
    event IncreaseAbsoluteCap(bytes32 indexed id, uint256 newCap);
    event DecreaseAbsoluteCap(bytes32 indexed id, uint256 newCap);
    event IncreaseRelativeCap(bytes32 indexed id, uint256 newRelativeCap);
    event DecreaseRelativeCap(bytes32 indexed id, uint256 newRelativeCap, uint256 index);
    event Deposit(address indexed sender, address indexed onBehalf, uint256 assets, uint256 shares);
    event Withdraw(
        address indexed sender, address indexed receiver, address indexed onBehalf, uint256 assets, uint256 shares
    );
    event Submit(address indexed sender, bytes data);
    event Revoke(address indexed sender, bytes data);
    event AccrueInterest(uint256 newTotalAssets);
    event ReallocateFromIdle(address indexed sender, address indexed adapter, bytes data, uint256 amount);
    event ReallocateToIdle(address indexed sender, address indexed adapter, bytes data, uint256 amount);
}
