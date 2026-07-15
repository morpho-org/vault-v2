// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Morpho Association
pragma solidity 0.8.28;

import {IVaultV2} from "../interfaces/IVaultV2.sol";
import {IPublicAllocator} from "./interfaces/IPublicAllocator.sol";
import {MarketParams} from "../adapters/interfaces/IMorphoMarketV1AdapterV2.sol";

/// @dev Specialized to Morpho Blue allocations through the MorphoMarketV1AdapterV2.
/// @dev To be usable, the PublicAllocator must be set as an allocator of the vault.
/// @dev The PublicAllocator inherits the vault's roles. The vault's allocators can set the absolute cap and
/// canDeallocate; the vault's sentinels can decrease the absolute cap and enable canDeallocate, to cut off public
/// inflows and allow public outflows for derisking; the vault's curator sets and claims the ETH penalty.
/// @dev Each reallocate call costs a penalty in native currency, set per vault by the curator. The penalty is accrued
/// per vault and can be claimed by the vault's curator.
/// @dev No-ops are allowed. Zero checks are not performed.
contract PublicAllocator is IPublicAllocator {
    /* STORAGE */

    mapping(address vault => mapping(bytes32 id => uint256)) public absoluteCap;
    mapping(address vault => mapping(bytes32 id => bool)) public canDeallocate;
    mapping(address vault => uint256) public ethPenalty;
    mapping(address vault => uint256) public accruedEthPenalty;

    /* AUTHORIZED FUNCTIONS */

    function setAbsoluteCap(address vault, address adapter, MarketParams calldata marketParams, uint256 newAbsoluteCap)
        external
    {
        bytes32 id = marketId(adapter, marketParams);
        require(
            IVaultV2(vault).isAllocator(msg.sender)
                || (newAbsoluteCap <= absoluteCap[vault][id] && IVaultV2(vault).isSentinel(msg.sender)),
            Unauthorized()
        );
        absoluteCap[vault][id] = newAbsoluteCap;
        emit SetAbsoluteCap(msg.sender, vault, address(adapter), marketParams, newAbsoluteCap);
    }

    function setCanDeallocate(address vault, address adapter, MarketParams calldata marketParams, bool newCanDeallocate)
        external
    {
        require(
            IVaultV2(vault).isAllocator(msg.sender) || (newCanDeallocate && IVaultV2(vault).isSentinel(msg.sender)),
            Unauthorized()
        );
        canDeallocate[vault][marketId(adapter, marketParams)] = newCanDeallocate;
        emit SetCanDeallocate(msg.sender, vault, address(adapter), marketParams, newCanDeallocate);
    }

    function setEthPenalty(address vault, uint256 newEthPenalty) external {
        require(msg.sender == IVaultV2(vault).curator(), Unauthorized());
        ethPenalty[vault] = newEthPenalty;
        emit SetEthPenalty(msg.sender, vault, newEthPenalty);
    }

    function claimEthPenalty(address vault, address payable receiver) external {
        require(msg.sender == IVaultV2(vault).curator(), Unauthorized());

        uint256 claimed = accruedEthPenalty[vault];
        accruedEthPenalty[vault] = 0;
        (bool success,) = receiver.call{value: claimed}("");
        require(success, EthTransferFailed());

        emit ClaimEthPenalty(msg.sender, vault, claimed, receiver);
    }

    /* PUBLIC FUNCTION */

    /// @dev The vault's caps are still enforced on the allocation, so this call reverts if it would exceed them.
    function reallocate(
        address vault,
        address deallocateAdapter,
        MarketParams calldata deallocateMarketParams,
        address allocateAdapter,
        MarketParams calldata allocateMarketParams,
        uint128 assets
    ) external payable {
        require(msg.value == ethPenalty[vault], IncorrectEthPenalty());
        if (msg.value > 0) accruedEthPenalty[vault] += msg.value;

        IVaultV2(vault).deallocate(address(deallocateAdapter), abi.encode(deallocateMarketParams), assets);
        IVaultV2(vault).allocate(address(allocateAdapter), abi.encode(allocateMarketParams), assets);

        bytes32 deallocateId = marketId(deallocateAdapter, deallocateMarketParams);
        require(canDeallocate[vault][deallocateId], CannotDeallocate());
        bytes32 allocateId = marketId(allocateAdapter, allocateMarketParams);
        require(IVaultV2(vault).allocation(allocateId) <= absoluteCap[vault][allocateId], AbsoluteCapExceeded());

        emit Reallocate(msg.sender, vault, allocateId, deallocateId, assets);
    }

    /* INTERNAL */

    /// @dev Returns the market's per-market vault id, exactly as keyed by the MorphoMarketV1AdapterV2.
    function marketId(address adapter, MarketParams calldata marketParams) internal pure returns (bytes32) {
        return keccak256(abi.encode("this/marketParams", address(adapter), marketParams));
    }
}
