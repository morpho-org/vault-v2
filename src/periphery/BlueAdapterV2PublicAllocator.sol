// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Morpho Association
pragma solidity 0.8.28;

import {IVaultV2} from "../interfaces/IVaultV2.sol";
import {IBlueAdapterV2PublicAllocator} from "./interfaces/IBlueAdapterV2PublicAllocator.sol";
import {IMorphoMarketV1AdapterV2Factory} from "../adapters/interfaces/IMorphoMarketV1AdapterV2Factory.sol";
import {ErrorsLib} from "../libraries/ErrorsLib.sol";
import {MarketParams} from "../../lib/morpho-blue/src/interfaces/IMorpho.sol";

/// @dev Specialized to Morpho Blue allocations through the MorphoMarketV1AdapterV2.
/// @dev To be usable, the BlueAdapterV2PublicAllocator must be set as an allocator of the vault.
/// @dev The BlueAdapterV2PublicAllocator inherits the vault's roles. The vault's allocators can set the absolute cap
/// and canDeallocate and canDeallocateFromIdle; the vault's sentinels can decrease the absolute cap, enable
/// canDeallocate, and disable canDeallocateFromIdle, to cut off public inflows and allow public outflows for derisking;
/// the vault's curator sets and claims the native penalty.
/// @dev Each reallocate call costs a penalty in native currency, set per vault by the curator. The penalty is accrued
/// per vault and can be claimed by the vault's curator.
/// @dev The vault's caps are still enforced on the allocation, so this call reverts if it would exceed them.
/// @dev The Public Allocator opens the door for anybody to manipulate relative caps through short-term deposits (but it
/// requires capital).
/// @dev No-ops are allowed. Zero checks are not performed.
contract BlueAdapterV2PublicAllocator is IBlueAdapterV2PublicAllocator {
    /* TYPES */

    /// @dev Packed into a single storage slot: bool (1 byte) + uint120 (15 bytes) + uint120 (15 bytes) = 31 bytes.
    struct VaultData {
        bool canDeallocateFromIdle;
        uint120 nativePenalty;
        uint120 accruedNativePenalty;
    }

    /* IMMUTABLES */

    address public immutable adapterFactory;

    /* STORAGE */

    mapping(address vault => mapping(bytes32 id => uint256)) public absoluteCap;
    mapping(address vault => mapping(bytes32 id => bool)) public canDeallocate;
    mapping(address vault => VaultData) internal _vaultData;

    /* CONSTRUCTOR */

    constructor(address _adapterFactory) {
        adapterFactory = _adapterFactory;
    }

    /* VIEW */

    function canDeallocateFromIdle(address vault) external view returns (bool) {
        return _vaultData[vault].canDeallocateFromIdle;
    }

    function nativePenalty(address vault) external view returns (uint256) {
        return _vaultData[vault].nativePenalty;
    }

    function accruedNativePenalty(address vault) external view returns (uint256) {
        return _vaultData[vault].accruedNativePenalty;
    }

    /* AUTHORIZED FUNCTIONS */

    function setAbsoluteCap(address vault, address adapter, MarketParams calldata marketParams, uint256 newAbsoluteCap)
        external
    {
        require(IMorphoMarketV1AdapterV2Factory(adapterFactory).isMorphoMarketV1AdapterV2(adapter), NotBlueAdapter());
        bytes32 id = vaultBlueId(adapter, marketParams);
        require(
            IVaultV2(vault).isAllocator(msg.sender)
                || (newAbsoluteCap <= absoluteCap[vault][id] && IVaultV2(vault).isSentinel(msg.sender)),
            Unauthorized()
        );
        absoluteCap[vault][id] = newAbsoluteCap;
        emit SetAbsoluteCap(msg.sender, vault, adapter, marketParams, newAbsoluteCap);
    }

    function setCanDeallocate(address vault, address adapter, MarketParams calldata marketParams, bool newCanDeallocate)
        external
    {
        require(IMorphoMarketV1AdapterV2Factory(adapterFactory).isMorphoMarketV1AdapterV2(adapter), NotBlueAdapter());
        require(
            IVaultV2(vault).isAllocator(msg.sender) || (newCanDeallocate && IVaultV2(vault).isSentinel(msg.sender)),
            Unauthorized()
        );
        canDeallocate[vault][vaultBlueId(adapter, marketParams)] = newCanDeallocate;
        emit SetCanDeallocate(msg.sender, vault, adapter, marketParams, newCanDeallocate);
    }

    function setCanDeallocateFromIdle(address vault, bool newCanDeallocate) external {
        require(
            IVaultV2(vault).isAllocator(msg.sender) || (!newCanDeallocate && IVaultV2(vault).isSentinel(msg.sender)),
            Unauthorized()
        );
        _vaultData[vault].canDeallocateFromIdle = newCanDeallocate;
        emit SetCanDeallocateFromIdle(msg.sender, vault, newCanDeallocate);
    }

    function setNativePenalty(address vault, uint256 newNativePenalty) external {
        require(msg.sender == IVaultV2(vault).curator(), Unauthorized());
        require(newNativePenalty <= type(uint120).max, ErrorsLib.CastOverflow());
        // forge-lint: disable-next-item(unsafe-typecast) safe because newNativePenalty <= type(uint120).max.
        _vaultData[vault].nativePenalty = uint120(newNativePenalty);
        emit SetNativePenalty(msg.sender, vault, newNativePenalty);
    }

    function claimNativePenalty(address vault, address payable receiver) external {
        require(msg.sender == IVaultV2(vault).curator(), Unauthorized());

        uint256 claimed = _vaultData[vault].accruedNativePenalty;
        _vaultData[vault].accruedNativePenalty = 0;
        (bool success,) = receiver.call{value: claimed}("");
        require(success, NativeTransferFailed());

        emit ClaimNativePenalty(msg.sender, vault, claimed, receiver);
    }

    /* PUBLIC FUNCTION */

    function reallocate(
        address vault,
        address adapter,
        MarketParams calldata deallocateMarketParams,
        MarketParams calldata allocateMarketParams,
        uint128 assets
    ) external payable {
        require(IMorphoMarketV1AdapterV2Factory(adapterFactory).isMorphoMarketV1AdapterV2(adapter), NotBlueAdapter());
        require(msg.value == _vaultData[vault].nativePenalty, IncorrectNativePenalty());
        // forge-lint: disable-next-item(unsafe-typecast) safe because msg.value == nativePenalty <= type(uint120).max.
        if (msg.value > 0) _vaultData[vault].accruedNativePenalty += uint120(msg.value);
        bytes32 deallocateId = vaultBlueId(adapter, deallocateMarketParams);
        require(canDeallocate[vault][deallocateId], CannotDeallocate());

        IVaultV2(vault).deallocate(adapter, abi.encode(deallocateMarketParams), assets);
        IVaultV2(vault).allocate(adapter, abi.encode(allocateMarketParams), assets);

        bytes32 allocateId = vaultBlueId(adapter, allocateMarketParams);
        require(IVaultV2(vault).allocation(allocateId) <= absoluteCap[vault][allocateId], AbsoluteCapExceeded());

        emit Reallocate(msg.sender, vault, allocateId, deallocateId, assets, msg.value);
    }

    function allocateFromIdle(address vault, address adapter, MarketParams calldata marketParams, uint128 assets)
        external
        payable
    {
        require(IMorphoMarketV1AdapterV2Factory(adapterFactory).isMorphoMarketV1AdapterV2(adapter), NotBlueAdapter());
        require(msg.value == _vaultData[vault].nativePenalty, IncorrectNativePenalty());
        // forge-lint: disable-next-item(unsafe-typecast) safe because msg.value == nativePenalty <= type(uint120).max.
        if (msg.value > 0) _vaultData[vault].accruedNativePenalty += uint120(msg.value);
        require(_vaultData[vault].canDeallocateFromIdle, CannotDeallocate());

        IVaultV2(vault).allocate(adapter, abi.encode(marketParams), assets);

        bytes32 allocateId = vaultBlueId(adapter, marketParams);
        require(IVaultV2(vault).allocation(allocateId) <= absoluteCap[vault][allocateId], AbsoluteCapExceeded());

        emit AllocateFromIdle(msg.sender, vault, allocateId, assets, msg.value);
    }

    /* INTERNAL */

    /// @dev Returns the market's per-market vault id, exactly as keyed by the MorphoMarketV1AdapterV2.
    /// @dev The caller must have checked that `adapter` was created by the expected factory (see the entry points),
    /// restricting all paths to Blue adapters.
    function vaultBlueId(address adapter, MarketParams calldata marketParams) internal pure returns (bytes32) {
        return keccak256(abi.encode("this/marketParams", adapter, marketParams));
    }
}
