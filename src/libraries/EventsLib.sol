// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Morpho Association
pragma solidity ^0.8.0;

library EventsLib {
    // ERC20 events
    event Approval(address indexed owner, address indexed spender, uint256 shares);
    event Transfer(address indexed from, address indexed to, uint256 shares);
    /// @dev Emitted when the allowance is updated by transferFrom (not when it is updated by permit, approve, withdraw,
    /// redeem because their respective events allow to track the allowance.
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
    event Allocate(address indexed sender, address indexed adapter, uint256 assets, bytes32[] ids, uint256 loss);
    event Deallocate(address indexed sender, address indexed adapter, uint256 assets, bytes32[] ids, uint256 loss);
    event ForceDeallocate(
        address indexed sender,
        address adapter,
        bytes data,
        uint256 assets,
        address indexed onBehalf,
        uint256 penaltyAssets
    );

    // Fee and interest events
    event AccrueInterest(
        uint256 previousTotalAssets, uint256 newTotalAssets, uint256 performanceFeeShares, uint256 managementFeeShares
    );

    // Timelock events
    event Revoke(address indexed sender, bytes4 indexed selector, bytes data);
    event Submit(bytes4 indexed selector, bytes data, uint256 executableAt);

    // Configuration events
    event SetOwner(address indexed newOwner);
    event SetCurator(address indexed newCurator);
    event SetIsSentinel(address indexed account, bool newIsSentinel);
    event SetName(string indexed newName);
    event SetSymbol(string indexed newSymbol);
    event SetIsAllocator(address indexed account, bool newIsAllocator);
    event SetSharesGate(address indexed newSharesGate);
    event SetReceiveAssetsGate(address indexed newReceiveAssetsGate);
    event SetSendAssetsGate(address indexed newSendAssetsGate);
    event SetVic(address indexed newVic);
    event SetIsAdapter(address indexed account, bool newIsAdapter);
    event AbdicateSubmit(bytes4 indexed selector);
    event DecreaseTimelock(bytes4 indexed selector, uint256 newDuration);
    event IncreaseTimelock(bytes4 indexed selector, uint256 newDuration);
    event SetLiquidityMarket(
        address indexed sender, address indexed newLiquidityAdapter, bytes indexed newLiquidityData
    );
    event SetPerformanceFee(uint256 newPerformanceFee);
    event SetPerformanceFeeRecipient(address indexed);
    event SetManagementFee(uint256 newManagementFee);
    event SetManagementFeeRecipient(address indexed);
    event DecreaseAbsoluteCap(bytes32 indexed id, bytes idData, uint256 newAbsoluteCap);
    event IncreaseAbsoluteCap(bytes32 indexed id, bytes idData, uint256 newAbsoluteCap);
    event DecreaseRelativeCap(bytes32 indexed id, bytes idData, uint256 newRelativeCap);
    event IncreaseRelativeCap(bytes32 indexed id, bytes idData, uint256 newRelativeCap);
    event SetForceDeallocatePenalty(address indexed adapter, uint256 forceDeallocatePenalty);
}
