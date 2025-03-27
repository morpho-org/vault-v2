// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity >=0.5.0;

import {IERC20} from "../../lib/openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";

interface IAdapter {
    function allocateIn(bytes memory data, uint256 amount) external returns (bytes32[] memory ids);
    function allocateOut(bytes memory data, uint256 amount) external returns (bytes32[] memory ids);
}

interface IVaultV2 {
    // State variables
    function asset() external view returns (IERC20);
    function owner() external view returns (address);
    function curator() external view returns (address);
    function guardian() external view returns (address);
    function isSentinel(address) external view returns (bool);
    function isAllocator(address) external view returns (bool);
    function performanceFee() external view returns (uint256);
    function managementFee() external view returns (uint256);
    function performanceFeeRecipient() external view returns (address);
    function managementFeeRecipient() external view returns (address);
    function irm() external view returns (address);
    function allocation(bytes32) external view returns (uint256);
    function lastUpdate() external view returns (uint256);
    function totalAssets() external view returns (uint256);
    function absoluteCap(bytes32) external view returns (uint256);
    function relativeCap(bytes32) external view returns (uint256);
    function validAt(bytes calldata) external view returns (uint256);
    function timelockDuration(bytes4) external view returns (uint64);

    // Owner actions
    function setPerformanceFeeRecipient(address) external;
    function setManagementFeeRecipient(address) external;
    function setOwner(address) external;
    function setCurator(address) external;
    function setIsSentinel(address, bool) external;
    function setGuardian(address) external;
    function setTreasurer(address) external;
    function increaseTimelock(bytes4, uint64) external;
    function decreaseTimelock(bytes4, uint64) external;
    function setAllocator(address) external;
    function unsetAllocator(address) external;

    // Treasurer actions
    function setPerformanceFee(uint256) external;
    function setManagementFee(uint256) external;

    // Curator actions
    function setIRM(address) external;
    function increaseAbsoluteCap(bytes32, uint256) external;
    function increaseRelativeCap(bytes32, uint256) external;
    function decreaseAbsoluteCap(bytes32, uint256) external;
    function decreaseRelativeCap(bytes32, uint256, uint256) external;

    // Allocator actions
    function reallocateFromIdle(address, bytes memory, uint256) external;
    function reallocateToIdle(address, bytes memory, uint256) external;

    // Exchange rate
    function accrueInterest() external;
    function accruedFeeShares() external returns (uint256, uint256, uint256, uint256, uint256);
    function convertToShares(uint256) external view returns (uint256);
    function convertToAssets(uint256) external view returns (uint256);

    // Timelocks
    function submit(bytes calldata) external;
    function revoke(bytes calldata) external;

    // User actions
    function deposit(uint256, address) external returns (uint256);
    function mint(uint256, address) external returns (uint256);
    function withdraw(uint256, address, address) external returns (uint256);
    function redeem(uint256, address, address) external returns (uint256);
}
