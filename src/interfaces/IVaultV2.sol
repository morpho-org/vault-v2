// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity >=0.5.0;

import {IERC20} from "./IERC20.sol";
import {IPermissionedToken} from "./IPermissionedToken.sol";

struct Caps {
    uint256 allocation;
    uint128 absoluteCap;
    uint64 relativeCap;
    bool enabled;
}

interface IVaultV2 is IERC20, IPermissionedToken {
    // Multicall
    function multicall(bytes[] memory data) external;

    // ERC-2612 (Permit)
    function permit(address owner, address spender, uint256 shares, uint256 deadline, uint8 v, bytes32 r, bytes32 s)
        external;
    function nonces(address owner) external view returns (uint256);
    function DOMAIN_SEPARATOR() external view returns (bytes32);

    // ERC-4626-v2
    function asset() external view returns (address);
    function totalAssets() external view returns (uint256);
    function previewDeposit(uint256 assets) external view returns (uint256 shares);
    function deposit(uint256 assets, address receiver) external returns (uint256 shares);
    function previewMint(uint256 shares) external view returns (uint256 assets);
    function mint(uint256 shares, address receiver) external returns (uint256 assets);
    function previewWithdraw(uint256 assets) external view returns (uint256 shares);
    function withdraw(uint256 assets, address receiver, address onBehalf) external returns (uint256 shares);
    function previewRedeem(uint256 shares) external view returns (uint256 assets);
    function redeem(uint256 shares, address receiver, address onBehalf) external returns (uint256 assets);

    // State variables
    function owner() external view returns (address);
    function curator() external view returns (address);
    function isSentinel(address account) external view returns (bool);
    function isAllocator(address account) external view returns (bool);
    function isAdapter(address account) external view returns (bool);
    function performanceFee() external view returns (uint96);
    function managementFee() external view returns (uint96);
    function performanceFeeRecipient() external view returns (address);
    function managementFeeRecipient() external view returns (address);
    function forceDeallocatePenalty(address adapter) external view returns (uint256);
    function vic() external view returns (address);
    function allocation(bytes32 id) external view returns (uint256);
    function lastUpdate() external view returns (uint64);
    function enterBlocked() external view returns (bool);
    function absoluteCap(bytes32 id) external view returns (uint256);
    function relativeCap(bytes32 id) external view returns (uint256);
    function enabled(bytes32 id) external view returns (bool);
    function executableAt(bytes memory data) external view returns (uint256);
    function timelock(bytes4 selector) external view returns (uint256);
    function liquidityAdapter() external view returns (address);
    function liquidityData() external view returns (bytes memory);
    function enterGate() external view returns (address);
    function exitGate() external view returns (address);

    // Owner actions
    function setOwner(address newOwner) external;
    function setExitGate(address newExitGate) external;
    function setEnterGate(address newEnterGate) external;
    function setCurator(address newCurator) external;
    function setIsSentinel(address account, bool isSentinel) external;

    // Curator actions
    function setVic(address newVic) external;
    function increaseTimelock(bytes4 selector, uint256 newDuration) external;
    function decreaseTimelock(bytes4 selector, uint256 newDuration) external;
    function abdicateSubmit(bytes4 selector) external;
    function setIsAllocator(address account, bool newIsAllocator) external;
    function setIsAdapter(address account, bool newIsAdapter) external;
    function disableId(bytes calldata idData) external;
    function setForceDeallocatePenalty(address adapter, uint256 newForceDeallocatePenalty) external;
    function increaseAbsoluteCap(bytes memory idData, uint256 newAbsoluteCap) external;
    function increaseRelativeCap(bytes memory idData, uint256 newRelativeCap) external;
    function decreaseAbsoluteCap(bytes memory idData, uint256 newAbsoluteCap) external;
    function decreaseRelativeCap(bytes memory idData, uint256 newRelativeCap) external;
    function setPerformanceFee(uint256 newPerformanceFee) external;
    function setManagementFee(uint256 newManagementFee) external;
    function setPerformanceFeeRecipient(address newPerformanceFeeRecipient) external;
    function setManagementFeeRecipient(address newManagementFeeRecipient) external;

    // Allocator actions
    function allocate(address adapter, bytes memory data, uint256 assets) external;
    function deallocate(address adapter, bytes memory data, uint256 assets) external;
    function setLiquidityAdapter(address newLiquidityAdapter) external;
    function setLiquidityData(bytes memory newLiquidityData) external;

    // Exchange rate
    function accrueInterest() external;
    function accrueInterestView()
        external
        view
        returns (uint256 newTotalAssets, uint256 performanceFeeShares, uint256 managementFeeShares);

    // Timelocks
    function submit(bytes memory data) external;
    function revoke(bytes memory data) external;

    // Force reallocate to idle
    function forceDeallocate(address adapter, bytes memory data, uint256 assets, address onBehalf)
        external
        returns (uint256 withdrawnShares);

    // Gate vault / permissioned token
    function canSend(address account) external returns (bool);
    function canReceive(address account) external returns (bool);
    function canSendUnderlyingAssets(address account) external returns (bool);
    function canReceiveUnderlyingAssets(address account) external returns (bool);
}
