// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Morpho Association
pragma solidity ^0.8.0;

library EventsLib {
    // ERC20 events
    event Approval(address indexed owner, address indexed spender, uint256 shares);
    event Transfer(address indexed from, address indexed to, uint256 shares);
    /// @dev Emitted when the allowance is updated by transferFrom (not when it is updated by permit, approve, withdraw,
    /// redeem because their respective events allow to track the allowance).
    event AllowanceUpdatedByTransferFrom(address indexed owner, address indexed spender, uint256 shares);
    event Permit(address indexed owner, address indexed spender, uint256 shares, uint256 nonce, uint256 deadline);

    // ERC4626 events
    event Deposit(address indexed sender, address indexed onBehalf, uint256 assets, uint256 shares);
    event Withdraw(
        address indexed sender, address indexed receiver, address indexed onBehalf, uint256 assets, uint256 shares
    );

    // Vault creation events
    event Constructor(address indexed owner, address indexed asset);

    // Allocation events
    event Allocate(address indexed sender, address indexed adapter, uint256 assets, bytes32[] ids, int256 change);
    event Deallocate(address indexed sender, address indexed adapter, uint256 assets, bytes32[] ids, int256 change);
    event ForceDeallocate(
        address indexed sender,
        address adapter,
        uint256 assets,
        address indexed onBehalf,
        bytes32[] ids,
        uint256 penaltyAssets
    );

    // Fee and interest events
    event AccrueInterest(
        uint256 previousTotalAssets, uint256 newTotalAssets, uint256 performanceFeeShares, uint256 managementFeeShares
    );

    // Timelock events
    event Revoke(address indexed sender, bytes4 indexed selector, bytes data);
    event Submit(bytes4 indexed selector, bytes data, uint256 executableAt);
    event Accept(bytes4 indexed selector, bytes data);

    // Configuration events
    event SetOwner(address indexed newOwner);
    event SetCurator(address indexed newCurator);
    event SetIsSentinel(address indexed account, bool newIsSentinel);
    event SetName(string newName);
    event SetSymbol(string newSymbol);
    event SetIsAllocator(address indexed account, bool newIsAllocator);
    event SetReceiveSharesGate(address indexed newReceiveSharesGate);
    event SetSendSharesGate(address indexed newSendSharesGate);
    event SetReceiveAssetsGate(address indexed newReceiveAssetsGate);
    event SetSendAssetsGate(address indexed newSendAssetsGate);
    event SetAdapterRegistry(address indexed newAdapterRegistry);
    event AddAdapter(address indexed account);
    event RemoveAdapter(address indexed account);
    event AbdicateSubmit(bytes4 indexed selector);
    event DecreaseTimelock(bytes4 indexed selector, uint256 newDuration);
    event IncreaseTimelock(bytes4 indexed selector, uint256 newDuration);
    event SetLiquidityAdapterAndData(
        address indexed sender, address indexed newLiquidityAdapter, bytes indexed newLiquidityData
    );
    event SetPerformanceFee(uint256 newPerformanceFee);
    event SetPerformanceFeeRecipient(address indexed newPerformanceFeeRecipient);
    event SetManagementFee(uint256 newManagementFee);
    event SetManagementFeeRecipient(address indexed newManagementFeeRecipient);
    event DecreaseAbsoluteCap(address indexed sender, bytes32 indexed id, bytes idData, uint256 newAbsoluteCap);
    event IncreaseAbsoluteCap(bytes32 indexed id, bytes idData, uint256 newAbsoluteCap);
    event DecreaseRelativeCap(address indexed sender, bytes32 indexed id, bytes idData, uint256 newRelativeCap);
    event IncreaseRelativeCap(bytes32 indexed id, bytes idData, uint256 newRelativeCap);
    event SetMaxRate(uint256 newMaxRate);
    event SetForceDeallocatePenalty(address indexed adapter, uint256 forceDeallocatePenalty);
}
