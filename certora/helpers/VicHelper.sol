// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.28;

contract VicHelper {

    bool shouldRevert;
    bool isReturnDataEmpty;

    function setShouldRevert(bool _shouldRevert) external {
        shouldRevert = _shouldRevert;
    }

    function setIsReturnDataEmpty(bool _isReturnDataEmpty) external {
        isReturnDataEmpty = _isReturnDataEmpty;
    }

    function interestPerSecond(uint256 totalAssets, uint256 elapsed) external view returns (uint256) {
        if (shouldRevert) {
            if (isReturnDataEmpty) {
                assembly ("memory-safe") { revert(0,0) }
            } else {
                revert("revert");
            }
        } else {
            if (isReturnDataEmpty) {
                assembly ("memory-safe") { return(0, 0) }
            } else {
                return 1;
            }
        }
    }
}
