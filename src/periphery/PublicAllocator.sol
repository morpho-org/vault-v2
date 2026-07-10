// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Morpho Association
pragma solidity 0.8.28;

import {IVaultV2} from "../interfaces/IVaultV2.sol";
import {IPublicAllocator} from "./interfaces/IPublicAllocator.sol";

/// @dev To be usable, the PublicAllocator must be set as an allocator of the vault.
/// @dev The PublicAllocator inherits the vault's roles. The vault's allocators can enable and disable canAllocate and
/// canDeallocate; the vault's sentinels can disable canAllocate and enable canDeallocate, to cut off public inflows and
/// allow public outflows for derisking; the vault's curator sets the penalty.
/// @dev Each reallocate call costs a penalty in native currency, set per vault by the curator. The penalty is accrued
/// per vault and can be claimed by the vault's curator.
/// @dev No-ops are allowed. Zero checks are not systematically performed.
contract PublicAllocator is IPublicAllocator {
    /* STORAGE */

    mapping(address vault => mapping(bytes32 key => bool)) public canAllocate;
    mapping(address vault => mapping(bytes32 key => bool)) public canDeallocate;
    mapping(address vault => uint256) public penalty;
    mapping(address vault => uint256) public accruedPenalty;

    /* CONFIGURATION FUNCTIONS */

    function setCanAllocate(address vault, address adapter, bytes calldata data, bool newCanAllocate) external {
        require(
            IVaultV2(vault).isAllocator(msg.sender) || (!newCanAllocate && IVaultV2(vault).isSentinel(msg.sender)),
            Unauthorized()
        );
        canAllocate[vault][keccak256(abi.encode(adapter, data))] = newCanAllocate;
        emit SetCanAllocate(msg.sender, vault, adapter, data, newCanAllocate);
    }

    function setCanDeallocate(address vault, address adapter, bytes calldata data, bool newCanDeallocate) external {
        require(
            IVaultV2(vault).isAllocator(msg.sender) || (newCanDeallocate && IVaultV2(vault).isSentinel(msg.sender)),
            Unauthorized()
        );
        canDeallocate[vault][keccak256(abi.encode(adapter, data))] = newCanDeallocate;
        emit SetCanDeallocate(msg.sender, vault, adapter, data, newCanDeallocate);
    }

    function setPenalty(address vault, uint256 newPenalty) external {
        require(msg.sender == IVaultV2(vault).curator(), Unauthorized());
        penalty[vault] = newPenalty;
        emit SetPenalty(msg.sender, vault, newPenalty);
    }

    /* CLAIM FUNCTION */

    function claimFee(address vault, address payable receiver) external {
        require(msg.sender == IVaultV2(vault).curator(), Unauthorized());

        uint256 claimed = accruedPenalty[vault];
        accruedPenalty[vault] = 0;
        receiver.transfer(claimed);

        emit ClaimFee(msg.sender, vault, claimed, receiver);
    }

    /* PUBLIC FUNCTION */

    /// @dev The vault's caps are still enforced on the allocation, so this call reverts if it would exceed them.
    function reallocate(
        address vault,
        address deallocateAdapter,
        bytes calldata deallocateData,
        address allocateAdapter,
        bytes calldata allocateData,
        uint128 assets
    ) external payable {
        require(msg.value == penalty[vault], IncorrectPenalty());
        if (msg.value > 0) accruedPenalty[vault] += msg.value;

        bytes32 deallocateKey = keccak256(abi.encode(deallocateAdapter, deallocateData));
        require(canDeallocate[vault][deallocateKey], CannotDeallocate());

        bytes32 allocateKey = keccak256(abi.encode(allocateAdapter, allocateData));
        require(canAllocate[vault][allocateKey], CannotAllocate());

        IVaultV2(vault).deallocate(deallocateAdapter, deallocateData, assets);
        IVaultV2(vault).allocate(allocateAdapter, allocateData, assets);

        emit Reallocate(msg.sender, vault, allocateKey, deallocateKey, assets);
    }
}
