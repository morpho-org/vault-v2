// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

library EventsLib {
    event Constructor(address indexed owner, address indexed asset);

    event Transfer(address indexed from, address indexed to, uint256 shares);

    /// @dev Emitted when the allowance is updated by transferFrom (not when it is updated by permit, approve, withdraw,
    /// redeem because their respective events allow to track the allowance.
    event AllowanceUpdatedByTransferFrom(address indexed owner, address indexed spender, uint256 shares);

    event Approval(address indexed owner, address indexed spender, uint256 shares);

    event Permit(address indexed owner, address indexed spender, uint256 shares, uint256 nonce, uint256 deadline);

    event SetOwner(address indexed newOwner);

    event SetCurator(address indexed newCurator);

    event SetVic(address indexed newVic);

    event SetIsSentinel(address indexed account, bool newIsSentinel);

    event SetIsAllocator(address indexed account, bool newIsAllocator);

    event SetExitGate(address indexed newExitGate);

    event SetEnterGate(address indexed newEnterGate);

    event SetPerformanceFeeRecipient(address indexed);

    event SetManagementFeeRecipient(address indexed);

    event SetIsAdapter(address indexed account, bool newIsAdapter);

    event IncreaseTimelock(bytes4 indexed selector, uint256 newDuration);

    event DecreaseTimelock(bytes4 indexed selector, uint256 newDuration);

    event FreezeSubmit(bytes4 indexed selector);

    event SetPerformanceFee(uint256 newPerformanceFee);

    event SetManagementFee(uint256 newManagementFee);

    event IncreaseAbsoluteCap(bytes32 indexed id, bytes idData, uint256 newAbsoluteCap);

    event DecreaseAbsoluteCap(bytes32 indexed id, bytes idData, uint256 newAbsoluteCap);

    event IncreaseRelativeCap(bytes32 indexed id, bytes idData, uint256 newRelativeCap);

    event DecreaseRelativeCap(bytes32 indexed id, bytes idData, uint256 newRelativeCap);

    event SetForceDeallocatePenalty(address indexed adapter, uint256 forceDeallocatePenalty);

    event Allocate(address indexed sender, address indexed adapter, uint256 assets, bytes32[] ids, int256 changeBefore);

    event Deallocate(
        address indexed sender, address indexed adapter, uint256 assets, bytes32[] ids, int256 changeBefore
    );

    event SetLiquidityAdapter(address indexed sender, address indexed newLiquidityAdapter);

    event SetLiquidityData(address indexed sender, bytes indexed newLiquidityData);

    event Deposit(address indexed sender, address indexed onBehalf, uint256 assets, uint256 shares);

    event Withdraw(
        address indexed sender, address indexed receiver, address indexed onBehalf, uint256 assets, uint256 shares
    );

    event Submit(bytes4 indexed selector, bytes data, uint256 executableAt);

    event Revoke(address indexed sender, bytes4 indexed selector, bytes data);

    event AccrueInterest(
        uint256 previousTotalAssets, uint256 newTotalAssets, uint256 performanceFeeShares, uint256 managementFeeShares
    );

    event ForceDeallocate(
        address indexed sender, address[] adapters, bytes[] data, uint256[] assets, address indexed onBehalf
    );

    event CreateVaultV2(address indexed owner, address indexed asset, address indexed vaultV2);
}
