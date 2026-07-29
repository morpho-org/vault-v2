// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Morpho Association
pragma solidity 0.8.28;

import {IVaultV2} from "../../interfaces/IVaultV2.sol";
import {IBluePublicAllocator, VaultData} from "./interfaces/IBluePublicAllocator.sol";
import {MarketParams} from "../../../lib/morpho-blue/src/interfaces/IMorpho.sol";

/// @dev To be usable, the BluePublicAllocator must be set as an allocator of the vault.
/// @dev Meant to be used with VaultV2 vaults only.
/// @dev Active adapters must be MorphoMarketV1AdapterV2 adapters, otherwise the public allocator's absolute cap system
/// could break.
/// @dev The vault's allocators can manage the public allocators' settings.
/// @dev Each reallocate and allocateFromIdle call costs a penalty in native currency, set per vault by the allocators.
/// The penalty is accrued per vault and can be claimed by the vault's allocators.
/// @dev The vault's caps are still enforced on the allocation, so allocation calls reverts if it would exceed them.
/// @dev The public allocator's caps are not checked on allocations from the vault (either by allocators or through
/// deposits).
/// @dev The BluePublicAllocator opens the door for anybody to manipulate relative caps through short-term deposits (but
/// it requires capital).
/// @dev reallocate and allocateFromIdle can be made to revert by anyone frontrunning them (not only allocators): an
/// allocate reverts if the vault cap is filled first, a deallocate reverts if shares stop covering assets.
contract BluePublicAllocator is IBluePublicAllocator {
    /* STORAGE */

    mapping(address vault => mapping(bytes32 id => uint256)) public absoluteCap;
    mapping(address vault => mapping(bytes32 id => bool)) public canDeallocate;
    mapping(address vault => mapping(address adapter => bool)) public isActiveAdapter;
    mapping(address vault => VaultData) public vaultData;

    /* MULTICALL */

    /// @dev Useful for EOAs to batch allocator calls.
    /// @dev Nonpayable so it cannot be used with reallocate and allocateFromIdle.
    /// @dev Does not return anything, because accounts who would use the return data would be contracts, which can do
    /// the multicall themselves.
    function multicall(bytes[] calldata data) external {
        for (uint256 i = 0; i < data.length; i++) {
            (bool success, bytes memory returnData) = address(this).delegatecall(data[i]);
            if (!success) {
                assembly ("memory-safe") {
                    revert(add(32, returnData), mload(returnData))
                }
            }
        }
    }

    /* AUTHORIZED FUNCTIONS */

    function setIsActiveAdapter(address vault, address adapter, bool newIsActiveAdapter) external {
        require(IVaultV2(vault).isAllocator(msg.sender), Unauthorized());
        isActiveAdapter[vault][adapter] = newIsActiveAdapter;
        emit SetIsActiveAdapter(msg.sender, vault, adapter, newIsActiveAdapter);
    }

    function setAbsoluteCap(address vault, address adapter, MarketParams calldata marketParams, uint256 newAbsoluteCap)
        external
    {
        bytes32 id = vaultBlueId(adapter, marketParams);
        require(IVaultV2(vault).isAllocator(msg.sender), Unauthorized());
        absoluteCap[vault][id] = newAbsoluteCap;
        emit SetAbsoluteCap(msg.sender, vault, adapter, marketParams, newAbsoluteCap);
    }

    function setCanDeallocate(address vault, address adapter, MarketParams calldata marketParams, bool newCanDeallocate)
        external
    {
        require(IVaultV2(vault).isAllocator(msg.sender), Unauthorized());
        canDeallocate[vault][vaultBlueId(adapter, marketParams)] = newCanDeallocate;
        emit SetCanDeallocate(msg.sender, vault, adapter, marketParams, newCanDeallocate);
    }

    function setCanAllocateFromIdle(address vault, bool newCanDeallocate) external {
        require(IVaultV2(vault).isAllocator(msg.sender), Unauthorized());
        vaultData[vault].canAllocateFromIdle = newCanDeallocate;
        emit SetCanAllocateFromIdle(msg.sender, vault, newCanDeallocate);
    }

    function setNativePenalty(address vault, uint256 newNativePenalty) external {
        require(IVaultV2(vault).isAllocator(msg.sender), Unauthorized());
        require(newNativePenalty <= type(uint120).max, CastOverflow());
        // forge-lint: disable-next-item(unsafe-typecast) safe because newNativePenalty <= type(uint120).max.
        vaultData[vault].nativePenalty = uint120(newNativePenalty);
        emit SetNativePenalty(msg.sender, vault, newNativePenalty);
    }

    function claimNativePenalty(address vault, address payable receiver) external {
        require(IVaultV2(vault).isAllocator(msg.sender), Unauthorized());
        uint256 claimed = vaultData[vault].accruedNativePenalty;
        vaultData[vault].accruedNativePenalty = 0;
        emit ClaimNativePenalty(msg.sender, vault, claimed, receiver);
        (bool success,) = receiver.call{value: claimed}("");
        require(success, NativeTransferFailed());
    }

    /* PUBLIC FUNCTION */

    function reallocate(
        address vault,
        address deallocateAdapter,
        MarketParams calldata deallocateMarketParams,
        address allocateAdapter,
        MarketParams calldata allocateMarketParams,
        uint128 assets
    ) external payable {
        require(msg.value == vaultData[vault].nativePenalty, IncorrectNativePenalty());
        // forge-lint: disable-next-item(unsafe-typecast) safe because msg.value == nativePenalty <= type(uint120).max.
        if (msg.value > 0) vaultData[vault].accruedNativePenalty += uint120(msg.value);
        require(isActiveAdapter[vault][deallocateAdapter], InactiveAdapter());
        require(isActiveAdapter[vault][allocateAdapter], InactiveAdapter());
        bytes32 deallocateId = vaultBlueId(deallocateAdapter, deallocateMarketParams);
        require(canDeallocate[vault][deallocateId], CannotDeallocate());

        IVaultV2(vault).deallocate(deallocateAdapter, abi.encode(deallocateMarketParams), assets);
        IVaultV2(vault).allocate(allocateAdapter, abi.encode(allocateMarketParams), assets);

        bytes32 allocateId = vaultBlueId(allocateAdapter, allocateMarketParams);
        require(IVaultV2(vault).allocation(allocateId) <= absoluteCap[vault][allocateId], AbsoluteCapExceeded());

        emit Reallocate(
            msg.sender, vault, deallocateAdapter, deallocateId, allocateAdapter, allocateId, assets, msg.value
        );
    }

    function allocateFromIdle(address vault, address adapter, MarketParams calldata marketParams, uint128 assets)
        external
        payable
    {
        require(msg.value == vaultData[vault].nativePenalty, IncorrectNativePenalty());
        // forge-lint: disable-next-item(unsafe-typecast) safe because msg.value == nativePenalty <= type(uint120).max.
        if (msg.value > 0) vaultData[vault].accruedNativePenalty += uint120(msg.value);
        require(isActiveAdapter[vault][adapter], InactiveAdapter());
        require(vaultData[vault].canAllocateFromIdle, CannotDeallocate());

        IVaultV2(vault).allocate(adapter, abi.encode(marketParams), assets);

        bytes32 allocateId = vaultBlueId(adapter, marketParams);
        require(IVaultV2(vault).allocation(allocateId) <= absoluteCap[vault][allocateId], AbsoluteCapExceeded());

        emit AllocateFromIdle(msg.sender, vault, adapter, allocateId, assets, msg.value);
    }

    /// @dev Returns the market's per-market vault id, exactly as keyed by the MorphoMarketV1AdapterV2.
    function vaultBlueId(address adapter, MarketParams calldata marketParams) internal pure returns (bytes32) {
        return keccak256(abi.encode("this/marketParams", adapter, marketParams));
    }
}
