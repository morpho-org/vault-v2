// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

library EventsLib {
    event Transfer(address indexed from, address indexed to, uint256 amount);
    event Approval(address indexed owner, address indexed spender, uint256 amount);
    event Permit(address indexed owner, address indexed spender, uint256 amount, uint256 nonce, uint256 deadline);
    event Construction(address indexed owner, address indexed asset);
    event SetOwner(address indexed owner);
    event SetCurator(address indexed curator);
    event SetTreasurer(address indexed treasurer);
    event SetIRM(address indexed irm);
    event SetIsSentinel(address indexed sentinel, bool isSentinel);
    event SetIsAllocator(address indexed allocator, bool isAllocator);
    event SetPerformanceFeeRecipient(address indexed);
    event SetManagementFeeRecipient(address indexed);
    event SetIsAdapter(address indexed adapter, bool isAdapter);
    event IncreaseTimelock(bytes4 indexed selector, uint256 newDuration);
    event DecreaseTimelock(bytes4 indexed selector, uint256 newDuration);
    event SetPerformanceFee(uint256 performanceFee);
    event SetManagementFee(uint256 managementFee);
    event IncreaseAbsoluteCap(bytes32 indexed id, uint256 newAbsoluteCap);
    event DecreaseAbsoluteCap(bytes32 indexed id, uint256 newAbsoluteCap);
    event IncreaseRelativeCap(bytes32 indexed id, uint256 newRelativeCap, uint256 index);
    event DecreaseRelativeCap(bytes32 indexed id, uint256 newRelativeCap, uint256 index);
    event ReallocateFromIdle(
        address indexed sender, address indexed adapter, bytes data, uint256 amount, bytes32[] ids
    );
    event ReallocateToIdle(address indexed sender, address indexed adapter, bytes data, uint256 amount, bytes32[] ids);
    event SetLiquidityAdapter(address indexed sender, address indexed liquidityAdapter);
    event SetLiquidityData(address indexed sender, bytes indexed data);
    event Deposit(address indexed sender, address indexed onBehalf, uint256 assets, uint256 shares);
    event Withdraw(
        address indexed sender, address indexed receiver, address indexed onBehalf, uint256 assets, uint256 shares
    );
    event Submit(address indexed sender, bytes data, uint256 validAt);
    event Revoke(address indexed sender, bytes data);
    event AccrueInterest(uint256 newTotalAssets, uint256 performanceFeeShares, uint256 managementFeeShares);
    event CreateVaultV2(address indexed vaultV2, address indexed owner, address indexed asset);
    event SetInterestPerSecond(uint256 irm);
}
