// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity >=0.5.0;

import {IERC20} from "../../lib/openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";

struct TimelockData {
    uint64 validAt;
    uint160 value;
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
    function cap(address) external view returns (uint160);
    function submitOwner(address) external;
    function submitCurator(address) external;
    function submitGuardian(address) external;
    function submitAllocator(address) external;
    function submitIRM(address) external;
    function submitCap(address, uint160) external;
    function reallocateFromIdle(address, uint256) external;
    function reallocateToIdle(address, uint256) external;
    function accrueInterest() external;
    function submitTimelockToUnzero(bytes4, uint64) external;
    function submitTimelockToIncrease(bytes4, uint64) external;
    function submitTimelockToDecrease(bytes4, uint64) external;

    function revoke(uint256) external;
    function accept(uint256) external;

    // Use trick to make a nice interface returning structs in memory.
    // function timelockData(uint256) external view returns (uint64, uint160);
    // function timelockConfig(bytes4) external view returns (uint64, uint64, uint64);
}
