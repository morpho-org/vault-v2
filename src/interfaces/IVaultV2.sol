// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity >=0.5.0;

import {IERC20} from "../../lib/openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";

interface IAdapter {
    function allocateIn(bytes memory data, uint256 amount) external returns (bytes32[] memory ids);
    function allocateOut(bytes memory data, uint256 amount) external returns (bytes32[] memory ids);
}

interface IVaultV2 {
    function asset() external view returns (IERC20);
    function totalAssets() external view returns (uint256);
    function deposit(uint256, address) external returns (uint256);
    function withdraw(uint256, address, address) external returns (uint256);
    function convertToAssets(uint256) external view returns (uint256);
    function balanceOf(address) external view returns (uint256);
    function maxWithdraw(address) external view returns (uint256);
    function owner() external view returns (address);
    function curator() external view returns (address);
    function guardian() external view returns (address);
    function irm() external view returns (address);
    function absoluteCap(bytes32) external view returns (uint256);
    function relativeCap(bytes32) external view returns (uint256);
    function allocation(bytes32) external view returns (uint256);
    function submit(bytes calldata) external;
    function setPerformanceFee(uint256) external;
    function setPerformanceFeeRecipient(address) external;
    function setManagementFee(uint256) external;
    function setManagementFeeRecipient(address) external;
    function setOwner(address) external;
    function setCurator(address) external;
    function setGuardian(address) external;
    function reallocateFromIdle(address, bytes memory, uint256) external;
    function reallocateToIdle(address, bytes memory, uint256) external;
    function addAdapter(address) external;
    function removeAdapter(address) external;
    function accrueInterest() external;
    function accruedFeeShares() external returns (uint256, uint256, uint256, uint256, uint256);
    function increaseTimelock(bytes4, uint64) external;
    function decreaseTimelock(bytes4, uint64) external;
    function increaseAbsoluteCap(bytes32, uint256) external;
    function decreaseAbsoluteCap(bytes32, uint256) external;
    function increaseRelativeCap(bytes32, uint256) external;
    function decreaseRelativeCap(bytes32, uint256, uint256) external;
    function setIRM(address) external;
}
