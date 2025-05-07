// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

library EventsLib {
    event Transfer(address indexed from, address indexed to, uint256 amount);
    event AllowanceUpdatedByTransferFrom(address indexed owner, address indexed spender, uint256 amount);
    event Approval(address indexed owner, address indexed spender, uint256 amount);
    event Permit(address indexed owner, address indexed spender, uint256 amount, uint256 nonce, uint256 deadline);
    event SetOwner(address indexed owner);
    event SetCurator(address indexed curator);
    event SetInterestController(address indexed interestController);
    event SetIsSentinel(address indexed account, bool isSentinel);
    event SetIsAllocator(address indexed account, bool isAllocator);
    event SetPerformanceFeeRecipient(address indexed);
    event SetManagementFeeRecipient(address indexed);
    event SetIsAdapter(address indexed account, bool isAdapter);
    event IncreaseTimelock(bytes4 indexed selector, uint256 newDuration);
    event DecreaseTimelock(bytes4 indexed selector, uint256 newDuration);
    event SetPerformanceFee(uint256 performanceFee);
    event SetManagementFee(uint256 managementFee);
    event IncreaseAbsoluteCap(bytes32 indexed id, bytes idData, uint256 newAbsoluteCap);
    event DecreaseAbsoluteCap(bytes32 indexed id, uint256 newAbsoluteCap);
    event IncreaseRelativeCap(bytes32 indexed id, uint256 newRelativeCap);
    event DecreaseRelativeCap(bytes32 indexed id, uint256 newRelativeCap);
    event SetForceReallocateToIdlePenalty(uint256 forceReallocateToIdleFee);
    event ReallocateFromIdle(address indexed sender, address indexed adapter, uint256 amount, bytes32[] ids);
    event ReallocateToIdle(address indexed sender, address indexed adapter, uint256 amount, bytes32[] ids);
    event SetLiquidityAdapter(address indexed sender, address indexed liquidityAdapter);
    event SetLiquidityData(address indexed sender, bytes indexed data);
    event Deposit(address indexed sender, address indexed onBehalf, uint256 assets, uint256 shares);
    event Withdraw(
        address indexed sender, address indexed receiver, address indexed onBehalf, uint256 assets, uint256 shares
    );
    event Submit(address indexed sender, bytes4 indexed selector, bytes data, uint256 validAt);
    event Revoke(address indexed sender, bytes4 indexed selector, bytes data);
    event AccrueInterest(
        uint256 newTotalAssets, uint256 previousTotalAssets, uint256 performanceFeeShares, uint256 managementFeeShares
    );
    event ForceReallocateToIdle(address indexed sender, address indexed onBehalf, uint256 assets);
    event CreateVaultV2(address indexed vaultV2, address indexed asset);
    event SetInterestPerSecond(uint256 interestPerSecond);
}
