// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.28;

import "../../src/VaultV2.sol";

contract VaultV2Harness is VaultV2 {
    constructor(address owner, address asset) VaultV2(owner, asset) {}

    function accrueInterestViewMocked() external view {
      uint256 elapsed = block.timestamp;
      UtilsLib.controlledStaticCall(vic, abi.encodeCall(IVic.interestPerSecond, (_totalAssets, elapsed)));
    }
}
