// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity >=0.5.0;

import {IERC20} from "../../lib/openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";

interface IMarket {
    function asset() external view returns (IERC20);
    function totalAssets() external view returns (uint256);
    function deposit(uint256, address) external returns (uint256);
    function withdraw(uint256, address, address) external returns (uint256);
    function convertToAssets(uint256) external view returns (uint256);
    function balanceOf(address) external view returns (uint256);
    function maxWithdraw(address) external view returns (uint256);
}

interface IVaultV2 is IMarket {
    // State variables
    function owner() external view returns (address);
    function curator() external view returns (address);
    function guardian() external view returns (address);
    function isSentinel(address) external view returns (bool);
    function isAllocator(address) external view returns (bool);
    function fee() external view returns (uint160);
    function feeRecipient() external view returns (address);
    function irm() external view returns (address);
    function lastUpdate() external view returns (uint256);
    function totalAssets() external view returns (uint256);
    function markets(uint256) external view returns (IMarket);
    function marketsLength() external view returns (uint256);
    function cap(address) external view returns (uint256);
    function validAt(bytes calldata) external view returns (uint256);
    function timelockDuration(bytes4) external view returns (uint64);

    // Authorized multicall
    function multicall(address allocator, bytes[] calldata bundle) external;

    // Owner actions
    function setFee(uint160) external;
    function setFeeRecipient(address) external;
    function setOwner(address) external;
    function setCurator(address) external;
    function setIsSentinel(address, bool) external;
    function setGuardian(address) external;
    function setTreasurer(address) external;
    function increaseTimelock(bytes4, uint64) external;
    function decreaseTimelock(bytes4, uint64) external;
    function setAllocator(address) external;
    function unsetAllocator(address) external;

    // Curator actions
    function newMarket(address) external;
    function dropMarket(uint8, address) external;
    function setIRM(address) external;
    function increaseCap(address, uint256) external;
    function decreaseCap(address, uint256) external;

    // Allocator actions
    function reallocateFromIdle(uint256, uint256) external;
    function reallocateToIdle(uint256, uint256) external;

    // Exchange rate
    function realAssets() external view returns (uint256);
    function accrueInterest() external;
    function accruedFeeShares() external returns (uint256 feeShares, uint256 newTotalAssets);
    function convertToShares(uint256) external view returns (uint256);
    function convertToAssets(uint256) external view returns (uint256);

    // Timelocks
    function submit(bytes calldata) external;
    function revoke(bytes calldata) external;
}
