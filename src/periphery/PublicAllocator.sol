// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Morpho Association
pragma solidity 0.8.28;

import {IVaultV2} from "../interfaces/IVaultV2.sol";
import {IPublicAllocator} from "./interfaces/IPublicAllocator.sol";

/// @dev To be usable, the PublicAllocator must be set as an allocator of the vault.
/// @dev The PublicAllocator inherits the vault's roles. The vault's allocators can enable and disable canAllocate;
/// the vault's sentinels can only disable canAllocate, to cut off public inflows (derisk); the vault's curator sets
/// the fee.
/// @dev Each reallocate call costs a fee in native currency, set per vault by the curator. The fee is sent to the
/// vault's curator on each call.
/// @dev No-ops are allowed. Zero checks are not systematically performed.
contract PublicAllocator is IPublicAllocator {
    /* STORAGE */

    mapping(address vault => mapping(bytes32 key => bool)) public canAllocate;
    mapping(address vault => uint256) public fee;

    /* CONFIGURATION FUNCTIONS */

    function setCanAllocate(address vault, address adapter, bytes calldata data, bool newCanAllocate) external {
        require(
            IVaultV2(vault).isAllocator(msg.sender) || (!newCanAllocate && IVaultV2(vault).isSentinel(msg.sender)),
            Unauthorized()
        );
        canAllocate[vault][keccak256(abi.encode(adapter, data))] = newCanAllocate;
        emit SetCanAllocate(msg.sender, vault, adapter, data, newCanAllocate);
    }

    function setFee(address vault, uint256 newFee) external {
        require(msg.sender == IVaultV2(vault).curator(), Unauthorized());
        fee[vault] = newFee;
        emit SetFee(msg.sender, vault, newFee);
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
        require(msg.value == fee[vault], IncorrectFee());
        if (msg.value > 0) {
            (bool success,) = payable(IVaultV2(vault).curator()).call{value: msg.value}("");
            require(success, FeeTransferFailed());
        }

        bytes32 allocateKey = keccak256(abi.encode(allocateAdapter, allocateData));
        require(canAllocate[vault][allocateKey], CannotAllocate());

        IVaultV2(vault).deallocate(deallocateAdapter, deallocateData, assets);
        IVaultV2(vault).allocate(allocateAdapter, allocateData, assets);

        bytes32 deallocateKey = keccak256(abi.encode(deallocateAdapter, deallocateData));
        emit Reallocate(msg.sender, vault, allocateKey, deallocateKey, assets);
    }
}
