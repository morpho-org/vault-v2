// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

library EventsLib {
    event Constructor(address indexed owner, address indexed asset);
    event Transfer(address indexed from, address indexed to, uint256 shares);
    event AllowanceUpdatedByTransferFrom(address indexed owner, address indexed spender, uint256 shares);
    event Approval(address indexed owner, address indexed spender, uint256 shares);
    event Permit(address indexed owner, address indexed spender, uint256 shares, uint256 nonce, uint256 deadline);
    event SetOwner(address indexed owner);
    event SetCurator(address indexed curator);
    event SetVic(address indexed vic);
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
    event DecreaseAbsoluteCap(bytes32 indexed id, bytes idData, uint256 newAbsoluteCap);
    event IncreaseRelativeCap(bytes32 indexed id, bytes idData, uint256 newRelativeCap);
    event DecreaseRelativeCap(bytes32 indexed id, bytes idData, uint256 newRelativeCap);
    event SetForceDeallocatePenalty(uint256 forceDeallocatePenalty);
    event SetExitPenalty(uint256 exitPenalty);
    event Allocate(address indexed sender, address indexed adapter, uint256 assets, bytes32[] ids);
    event Deallocate(address indexed sender, address indexed adapter, uint256 assets, bytes32[] ids);
    event SetLiquidityAdapter(address indexed sender, address indexed liquidityAdapter);
    event SetLiquidityData(address indexed sender, bytes indexed data);
    event Deposit(address indexed sender, address indexed onBehalf, uint256 assets, uint256 shares);
    event Withdraw(
        address indexed sender, address indexed receiver, address indexed onBehalf, uint256 assets, uint256 shares
    );
    event Submit(address indexed sender, bytes4 indexed selector, bytes data, uint256 validAt);
    event Revoke(address indexed sender, bytes4 indexed selector, bytes data);
    event AccrueInterest(
        uint256 previousTotalAssets, uint256 newTotalAssets, uint256 performanceFeeShares, uint256 managementFeeShares
    );
    event ForceDeallocate(address indexed sender, address indexed onBehalf, uint256 assets);
    event CreateVaultV2(address indexed owner, address indexed asset, address indexed vaultV2);
}
