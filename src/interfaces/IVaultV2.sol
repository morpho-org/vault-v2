// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity >=0.5.0;

import {IERC20} from "../../lib/openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";

struct TimelockData {
    uint64 validAt;
    uint160 value;
}

struct TimelockConfig {
    bool canIncrease;
    uint64 duration;
}

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
    function markets(uint256) external view returns (IMarket);
    function marketsLength() external view returns (uint256);
    function cap(address) external view returns (uint160);
    function setOwner(address) external;
    function setCurator(address) external;
    function setGuardian(address) external;
    function setAllocator(address) external;
    function newMarket(address) external;
    function dropMarket(uint8) external;
    function reallocateFromIdle(uint256, uint256) external;
    function reallocateToIdle(uint256, uint256) external;
    function realAssets() external view returns (uint256);
    function accrueInterest() external;
    function setTimelock(bytes4, TimelockConfig memory) external;
    function revokeTimelock(bytes4) external;
    function setCap(address, uint160) external;
    function setIRM(address) external;
    // Use trick to make a nice interface returning structs in memory.
    function timelockData(bytes24) external view returns (uint64, uint160);
    function timelockConfig(bytes4) external view returns (bool, uint64);
}
