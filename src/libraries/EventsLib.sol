// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

library EventsLib {
    event AbdicateSubmit(bytes4 indexed selector);

    event AccrueInterest(
        uint256 previousTotalAssets, uint256 newTotalAssets, uint256 performanceFeeShares, uint256 managementFeeShares
    );

    event Allocate(address indexed sender, address indexed adapter, uint256 assets, bytes32[] ids, uint256 loss);

    /// @dev Emitted when the allowance is updated by transferFrom (not when it is updated by permit, approve, withdraw,
    /// redeem because their respective events allow to track the allowance.
    event AllowanceUpdatedByTransferFrom(address indexed owner, address indexed spender, uint256 shares);

    event Approval(address indexed owner, address indexed spender, uint256 shares);

    event Constructor(address indexed owner, address indexed asset);

    event CreateVaultV2(address indexed owner, address indexed asset, address indexed vaultV2);

    event Deallocate(address indexed sender, address indexed adapter, uint256 assets, bytes32[] ids, uint256 loss);

    event DecreaseAbsoluteCap(bytes32 indexed id, bytes idData, uint256 newAbsoluteCap);

    event DecreaseRelativeCap(bytes32 indexed id, bytes idData, uint256 newRelativeCap);

    event DecreaseTimelock(bytes4 indexed selector, uint256 newDuration);

    event Deposit(address indexed sender, address indexed onBehalf, uint256 assets, uint256 shares);

    event ForceDeallocate(
        address indexed sender,
        address adapter,
        bytes data,
        uint256 assets,
        address indexed onBehalf,
        uint256 penaltyAssets
    );

    event IncreaseAbsoluteCap(bytes32 indexed id, bytes idData, uint256 newAbsoluteCap);

    event IncreaseRelativeCap(bytes32 indexed id, bytes idData, uint256 newRelativeCap);

    event IncreaseTimelock(bytes4 indexed selector, uint256 newDuration);

    event Permit(address indexed owner, address indexed spender, uint256 shares, uint256 nonce, uint256 deadline);

    event Revoke(address indexed sender, bytes4 indexed selector, bytes data);

    event SetCurator(address indexed newCurator);

    event SetForceDeallocatePenalty(address indexed adapter, uint256 forceDeallocatePenalty);

    event SetIsAdapter(address indexed account, bool newIsAdapter);

    event SetIsAllocator(address indexed account, bool newIsAllocator);

    event SetIsSentinel(address indexed account, bool newIsSentinel);

    event SetLiquidityMarket(
        address indexed sender, address indexed newLiquidityAdapter, bytes indexed newLiquidityData
    );

    event SetManagementFee(uint256 newManagementFee);

    event SetManagementFeeRecipient(address indexed);

    event SetName(string indexed newName);

    event SetOwner(address indexed newOwner);

    event SetPerformanceFee(uint256 newPerformanceFee);

    event SetPerformanceFeeRecipient(address indexed);

    event SetReceiveAssetsGate(address indexed newReceiveAssetsGate);

    event SetSendAssetsGate(address indexed newSendAssetsGate);

    event SetSharesGate(address indexed newSharesGate);

    event SetSymbol(string indexed newSymbol);

    event SetVic(address indexed newVic);

    event Submit(bytes4 indexed selector, bytes data, uint256 executableAt);

    event Transfer(address indexed from, address indexed to, uint256 shares);

    event Withdraw(
        address indexed sender, address indexed receiver, address indexed onBehalf, uint256 assets, uint256 shares
    );
}
