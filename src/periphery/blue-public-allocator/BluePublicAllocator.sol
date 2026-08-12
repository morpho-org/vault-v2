// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Morpho Association
pragma solidity 0.8.28;

import {IVaultV2} from "../../interfaces/IVaultV2.sol";
import {IVaultV2Factory} from "../../interfaces/IVaultV2Factory.sol";
import {IBluePublicAllocator, VaultData} from "./interfaces/IBluePublicAllocator.sol";
import {MarketParams} from "../../../lib/morpho-blue/src/interfaces/IMorpho.sol";
import {WAD} from "../../libraries/ConstantsLib.sol";
import {MathLib} from "../../libraries/MathLib.sol";
import {SafeERC20Lib} from "../../libraries/SafeERC20Lib.sol";

/// @dev To be usable, the BluePublicAllocator must be set as an allocator of the vault.
/// @dev Meant to be used with VaultV2 vaults only.
/// @dev Active adapters must be MorphoMarketV1AdapterV2 adapters, otherwise the public allocator's absolute cap system
/// could break.
/// @dev The vault's allocators can manage the public allocators' settings.
/// @dev Each reallocate and allocateFromIdle call costs a proportional penalty, paid by the caller in the vault's
/// asset. The penalty is set per vault by the allocators and is transferred directly to the vault (a donation, which
/// increases the rate like forceDeallocate penalties).
/// @dev The penalty parameter of reallocate and allocateFromIdle protects callers against penalty changes between
/// signing and execution.
/// @dev The vault's forceDeallocatePenalty is ignored by this contract.
/// @dev The vault's caps are still enforced on the allocation, so allocation calls reverts if it would exceed them.
/// @dev The public allocator's caps are not checked on allocations from the vault (either by allocators or through
/// deposits).
/// @dev The BluePublicAllocator opens the door for anybody to manipulate relative caps through short-term deposits (but
/// it requires capital).
/// @dev reallocate and allocateFromIdle can be made to revert by anyone frontrunning them (not only allocators): an
/// allocate reverts if the vault cap is filled first, a deallocate reverts if shares stop covering assets.
/// @dev Reallocations (notably through this contract) can reduce the vault's "direct" liquidity by pulling assets from
/// idle and from the liquidity market. It can also block deposit by reaching the liquidity market's caps.
contract BluePublicAllocator is IBluePublicAllocator {
    /* IMMUTABLES */

    address public immutable vaultV2Factory;

    /* STORAGE */

    mapping(address vault => mapping(bytes32 id => uint256)) public absoluteCap;
    mapping(address vault => mapping(bytes32 id => bool)) public canPullFromMarket;
    mapping(address vault => mapping(address adapter => bool)) public isActiveAdapter;
    mapping(address vault => VaultData) public vaultData;

    /* CONSTRUCTOR */

    constructor(address _vaultV2Factory) {
        vaultV2Factory = _vaultV2Factory;
    }

    /* MULTICALL */

    /// @dev Useful for EOAs to batch allocator calls.
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
        require(IVaultV2Factory(vaultV2Factory).isVaultV2(vault), NotVaultV2());
        require(IVaultV2(vault).isAllocator(msg.sender), Unauthorized());
        isActiveAdapter[vault][adapter] = newIsActiveAdapter;
        emit SetIsActiveAdapter(msg.sender, vault, adapter, newIsActiveAdapter);
    }

    function setAbsoluteCap(address vault, address adapter, MarketParams calldata marketParams, uint256 newAbsoluteCap)
        external
    {
        require(IVaultV2Factory(vaultV2Factory).isVaultV2(vault), NotVaultV2());
        bytes32 id = vaultBlueId(adapter, marketParams);
        require(IVaultV2(vault).isAllocator(msg.sender), Unauthorized());
        absoluteCap[vault][id] = newAbsoluteCap;
        emit SetAbsoluteCap(msg.sender, vault, adapter, marketParams, newAbsoluteCap);
    }

    function setCanPullFromMarket(
        address vault,
        address adapter,
        MarketParams calldata marketParams,
        bool newCanPullFromMarket
    ) external {
        require(IVaultV2Factory(vaultV2Factory).isVaultV2(vault), NotVaultV2());
        require(IVaultV2(vault).isAllocator(msg.sender), Unauthorized());
        canPullFromMarket[vault][vaultBlueId(adapter, marketParams)] = newCanPullFromMarket;
        emit SetCanPullFromMarket(msg.sender, vault, adapter, marketParams, newCanPullFromMarket);
    }

    function setCanPullFromIdle(address vault, bool newCanPullFromIdle) external {
        require(IVaultV2Factory(vaultV2Factory).isVaultV2(vault), NotVaultV2());
        require(IVaultV2(vault).isAllocator(msg.sender), Unauthorized());
        vaultData[vault].canPullFromIdle = newCanPullFromIdle;
        emit SetCanPullFromIdle(msg.sender, vault, newCanPullFromIdle);
    }

    function setPenalty(address vault, uint64 newPenalty) external {
        require(IVaultV2Factory(vaultV2Factory).isVaultV2(vault), NotVaultV2());
        require(IVaultV2(vault).isAllocator(msg.sender), Unauthorized());
        require(newPenalty <= WAD, PenaltyTooHigh());
        vaultData[vault].penalty = newPenalty;
        emit SetPenalty(msg.sender, vault, newPenalty);
    }

    /* PUBLIC FUNCTION */

    function reallocate(
        address vault,
        address deallocateAdapter,
        MarketParams calldata deallocateMarketParams,
        address allocateAdapter,
        MarketParams calldata allocateMarketParams,
        uint128 assets,
        uint64 penalty
    ) external {
        require(vaultData[vault].penalty == penalty, IncorrectPenalty());
        uint256 penaltyAssets = MathLib.mulDivUp(assets, penalty, WAD);
        if (penaltyAssets > 0) {
            SafeERC20Lib.safeTransferFrom(allocateMarketParams.loanToken, msg.sender, vault, penaltyAssets);
        }
        require(isActiveAdapter[vault][deallocateAdapter], InactiveAdapter());
        require(isActiveAdapter[vault][allocateAdapter], InactiveAdapter());
        bytes32 deallocateId = vaultBlueId(deallocateAdapter, deallocateMarketParams);
        require(canPullFromMarket[vault][deallocateId], CannotPullFromMarket());

        IVaultV2(vault).deallocate(deallocateAdapter, abi.encode(deallocateMarketParams), assets);
        IVaultV2(vault).allocate(allocateAdapter, abi.encode(allocateMarketParams), assets);

        bytes32 allocateId = vaultBlueId(allocateAdapter, allocateMarketParams);
        require(IVaultV2(vault).allocation(allocateId) <= absoluteCap[vault][allocateId], AbsoluteCapExceeded());

        emit Reallocate(
            msg.sender, vault, deallocateAdapter, deallocateId, allocateAdapter, allocateId, assets, penaltyAssets
        );
    }

    function allocateFromIdle(
        address vault,
        address adapter,
        MarketParams calldata marketParams,
        uint128 assets,
        uint64 penalty
    ) external {
        require(vaultData[vault].penalty == penalty, IncorrectPenalty());
        uint256 penaltyAssets = MathLib.mulDivUp(assets, penalty, WAD);
        if (penaltyAssets > 0) SafeERC20Lib.safeTransferFrom(marketParams.loanToken, msg.sender, vault, penaltyAssets);
        require(isActiveAdapter[vault][adapter], InactiveAdapter());
        require(vaultData[vault].canPullFromIdle, CannotPullFromIdle());

        IVaultV2(vault).allocate(adapter, abi.encode(marketParams), assets);

        bytes32 allocateId = vaultBlueId(adapter, marketParams);
        require(IVaultV2(vault).allocation(allocateId) <= absoluteCap[vault][allocateId], AbsoluteCapExceeded());

        emit AllocateFromIdle(msg.sender, vault, adapter, allocateId, assets, penaltyAssets);
    }

    /// @dev Returns the market's per-market vault id, exactly as keyed by the MorphoMarketV1AdapterV2.
    function vaultBlueId(address adapter, MarketParams calldata marketParams) internal pure returns (bytes32) {
        return keccak256(abi.encode("this/marketParams", adapter, marketParams));
    }
}
