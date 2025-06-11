// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.28;

import "../../src/VaultV2.sol";

contract VaultV2Harness is VaultV2 {
    constructor(address owner, address asset) VaultV2(owner, asset) {}

    function accrueInterestViewMocked() external view {
        uint256 elapsed = block.timestamp;

        (bool success, bytes memory data) =
            address(vic).staticcall(abi.encodeCall(IVic.interestPerSecond, (_totalAssets, elapsed)));
        uint256 output;
        if (success) {
            assembly ("memory-safe") {
                output := mload(add(data, 32))
            }
        }
    }
}
