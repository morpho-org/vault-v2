// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity >=0.5.0;

import {IERC20} from "./IERC20.sol";

interface IVaultV2 is IERC20 {
    // Multicall
    function multicall(bytes[] calldata data) external;

    // ERC-2612 (Permit)
    function permit(address owner, address spender, uint256 shares, uint256 deadline, uint8 v, bytes32 r, bytes32 s)
        external;
    function nonces(address owner) external view returns (uint256 nonce);
    function DOMAIN_SEPARATOR() external view returns (bytes32 domainSeparator);

    // ERC-4626-v2
    function asset() external view returns (address asset);
    function totalAssets() external view returns (uint256 totalAssets);
    function previewDeposit(uint256 assets) external view returns (uint256 previewDeposit);
    function deposit(uint256 assets, address receiver) external returns (uint256 shares);
    function previewMint(uint256 shares) external view returns (uint256 previewMint);
    function mint(uint256 shares, address receiver) external returns (uint256 assets);
    function previewWithdraw(uint256 assets) external view returns (uint256 previewWithdraw);
    function withdraw(uint256 assets, address receiver, address owner) external returns (uint256 shares);
    function previewRedeem(uint256 shares) external view returns (uint256 previewRedeem);
    function redeem(uint256 shares, address receiver, address owner) external returns (uint256 assets);

    // State variables
    function owner() external view returns (address owner);
    function curator() external view returns (address curator);
    function isSentinel(address account) external view returns (bool isSentinel);
    function isAllocator(address account) external view returns (bool isAllocator);
    function isAdapter(address account) external view returns (bool isAdapter);
    function performanceFee() external view returns (uint256 performanceFee);
    function managementFee() external view returns (uint256 managementFee);
    function performanceFeeRecipient() external view returns (address performanceFeeRecipient);
    function managementFeeRecipient() external view returns (address managementFeeRecipient);
    function forceReallocateToIdlePenalty() external view returns (uint256 forceReallocateToIdlePenalty);
    function vic() external view returns (address vic);
    function allocation(bytes32 id) external view returns (uint256 allocation);
    function lastUpdate() external view returns (uint256 lastUpdate);
    function absoluteCap(bytes32 id) external view returns (uint256 absoluteCap);
    function relativeCap(bytes32 id) external view returns (uint256 relativeCap);
    function idsWithRelativeCap(uint256 index) external view returns (bytes32 id);
    function executableAt(bytes calldata data) external view returns (uint256 executableAt);
    function timelock(bytes4 selector) external view returns (uint256 timelock);
    function liquidityAdapter() external view returns (address liquidityAdapter);
    function liquidityData() external view returns (bytes memory liquidityData);

    // Getters
    function idsWithRelativeCapLength() external view returns (uint256 idsWithRelativeCapLength);

    // Owner actions
    function setOwner(address account) external;
    function setCurator(address account) external;
    function setIsSentinel(address account, bool isSentinel) external;

    // Curator actions
    function setVic(address vic) external;
    function increaseTimelock(bytes4 selector, uint256 duration) external;
    function decreaseTimelock(bytes4 selector, uint256 duration) external;
    function setIsAllocator(address account, bool isAllocator) external;
    function setIsAdapter(address account, bool isAdapter) external;
    function setForceReallocateToIdlePenalty(uint256 penalty) external;
    function increaseAbsoluteCap(bytes memory idData, uint256 absoluteCap) external;
    function increaseRelativeCap(bytes memory idData, uint256 relativeCap) external;
    function decreaseAbsoluteCap(bytes memory idData, uint256 absoluteCap) external;
    function decreaseRelativeCap(bytes memory idData, uint256 relativeCap) external;
    function setPerformanceFee(uint256 performanceFee) external;
    function setManagementFee(uint256 managementFee) external;
    function setPerformanceFeeRecipient(address recipient) external;
    function setManagementFeeRecipient(address recipient) external;

    // Allocator actions
    function reallocateFromIdle(address adapter, bytes memory data, uint256 assets) external;
    function reallocateToIdle(address adapter, bytes memory data, uint256 assets) external;
    function setLiquidityAdapter(address adapter) external;
    function setLiquidityData(bytes memory data) external;

    // Exchange rate
    function accrueInterest() external;
    function accrueInterestView()
        external
        view
        returns (uint256 newTotalAssets, uint256 performanceFeeShares, uint256 managementFeeShares);

    // Timelocks
    function submit(bytes calldata data) external;
    function revoke(bytes calldata data) external;

    // Force reallocate to idle
    function forceReallocateToIdle(
        address[] memory adapters,
        bytes[] memory data,
        uint256[] memory assets,
        address onBehalf
    ) external returns (uint256 withdrawnShares);
}
