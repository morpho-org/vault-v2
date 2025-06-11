// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.28;

contract VicHelper {

    bool shouldRevert;
    uint returnDataLength;

    function setShouldRevert(bool _shouldRevert) external {
        shouldRevert = _shouldRevert;
    }

    function setReturnDataLength(uint256 _returnDataLength) external {
        returnDataLength = _returnDataLength;
    }

    function interestPerSecond(uint256 totalAssets, uint256 elapsed) external view returns (uint256 r) {
        uint _returnDataLength = returnDataLength;
        if (shouldRevert) {
            assembly ("memory-safe") {
                revert(0, _returnDataLength)
            }
        } else {
            assembly ("memory-safe") {
                return(0, _returnDataLength)
            }
        }
    }
}
