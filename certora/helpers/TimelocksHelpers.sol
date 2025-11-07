// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Morpho Association
pragma solidity 0.8.28;

import "../../src/VaultV2.sol";
import "../../src/interfaces/IVaultV2.sol";

// Helper for timelock verification
contract TimelockManagerHelpers {
    VaultV2 public vault;
    
    // Extract selector from calldata
    function getSelector(bytes memory data) public pure returns (bytes4) {
        require(data.length >= 4, "Data too short");
        return bytes4(data);
    }

    // Check if data is for decreaseTimelock
    function isDecreaseTimelock(bytes memory data) public pure returns (bool) {
        /*if (bytes4(data) == IVaultV2.decreaseTimelock.selector) {
            return true;
        } 
        return false;*/
        return true;
    }
    
    function extractDecreaseTimelockArgs(bytes memory data) public pure returns (bytes4 targetSelector, uint256 newTimelock) {
        require(data.length >= 68, "Invalid decreaseTimelock data");
        bytes4 selector = bytes4(data);
        require(selector == IVaultV2.decreaseTimelock.selector, "Not decreaseTimelock");
        
        // Skip the first 4 bytes (selector) and decode the parameters
        bytes memory params = new bytes(data.length - 4);
        for (uint i = 0; i < params.length; i++) {
            params[i] = data[i + 4];
        }
        
        (targetSelector, newTimelock) = abi.decode(params, (bytes4, uint256));
    }

    
}

// Helper verifying execution is blocked before minimum timelock expires
contract BeforeMinimumTimeChecker {
    VaultV2 public vault;
    
    fallback() external {
        bytes4 selector = bytes4(msg.data);
        require(!vault.abdicated(selector), "Function is abdicated");
        
        uint256 currentTime = block.timestamp;
        uint256 currentTimelockValue = vault.timelock(selector);
        require(currentTime + currentTimelockValue < type(uint256).max, "Overflow");
        uint256 time1 = currentTime + currentTimelockValue;
        
        uint256 alreadySubmittedTime = vault.executableAt(msg.data);
        uint256 time2 = alreadySubmittedTime == 0 ? type(uint256).max : alreadySubmittedTime;
        
        uint256 minTime = time1 < time2 ? time1 : time2;
        require(currentTime < minTime, "Not before minimum time");
    }
}

// Helper verifying data has not been submitted
contract NotSubmittedHarness {
    VaultV2 public vault;
    
    fallback() external {
        bytes4 selector = bytes4(msg.data);
        require(!vault.abdicated(selector), "Function is abdicated");
        uint256 alreadySubmittedTime = vault.executableAt(msg.data);
        require(alreadySubmittedTime == 0, "Data already submitted");
    }
}

// Helper for revoke functionality
contract RevokeHarness {
    VaultV2 public vault;
    
    fallback() external {
        // Make sure it's executable before revoking
        bytes4 selector = bytes4(msg.data);
        require(!vault.abdicated(selector), "Function is abdicated");
        uint256 execTime = vault.executableAt(msg.data);
        require(execTime != 0, "Data not submitted");
        
        // Check if timelock expired
        require(block.timestamp >= execTime, "Timelock not expired");

        // Now revoke using msg.data
        vault.revoke(msg.data);
    }
}
