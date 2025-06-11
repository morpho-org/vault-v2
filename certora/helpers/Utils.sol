// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.28;

import "../../src/libraries/ConstantsLib.sol";

contract Utils {
    function toBytes4(bytes memory data) public pure returns (bytes4) {
        return bytes4(data);
    }

    function wad() external pure returns (uint256) {
        return WAD;
    }

    function maxRatePerSecond() external pure returns (uint256) {
        return MAX_RATE_PER_SECOND;
    }

    function timelockCap() external pure returns (uint256) {
        return TIMELOCK_CAP;
    }

    function maxPerformanceFee() external pure returns (uint256) {
        return MAX_PERFORMANCE_FEE;
    }

    function maxManagementFee() external pure returns (uint256) {
        return MAX_MANAGEMENT_FEE;
    }

    function maxForceDeallocatePenalty() external pure returns (uint256) {
        return MAX_FORCE_DEALLOCATE_PENALTY;
    }
}
