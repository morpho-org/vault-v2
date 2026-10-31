// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Morpho Association
pragma solidity 0.8.28;

import {IVaultV2} from "../interfaces/IVaultV2.sol";
import {IMorphoMarketV1AdapterV2} from "../adapters/interfaces/IMorphoMarketV1AdapterV2.sol";

interface RevokeSource {
    function revokeData() external view returns (bytes memory);
}

/// @dev This contract can safely have the sentinel role in any vault.
contract Revoker {
    error NotSentinel();
    error InvalidTarget();
    error DeploymentFailed();

    /// @dev Deploys a contract that returns bytes to revoke on target.
    function revoke(address vault, address target, bytes memory creationCode) external {
        require(target == vault || IMorphoMarketV1AdapterV2(target).parentVault() == vault, InvalidTarget());
        require(IVaultV2(vault).isSentinel(msg.sender), NotSentinel());

        address source;
        assembly ("memory-safe") {
            source := create(0, add(creationCode, 32), mload(creationCode))
        }
        require(source != address(0), DeploymentFailed());

        IVaultV2(target).revoke(RevokeSource(source).revokeData());
    }
}
