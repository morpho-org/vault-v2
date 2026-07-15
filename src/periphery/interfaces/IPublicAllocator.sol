// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Morpho Association
pragma solidity >=0.5.0;

import {MarketParams} from "../../adapters/interfaces/IMorphoMarketV1AdapterV2.sol";

interface IPublicAllocator {
    /* EVENTS */

    event SetAbsoluteCap(
        address indexed sender, address indexed vault, address adapter, MarketParams marketParams, uint256 absoluteCap
    );
    event SetCanDeallocate(
        address indexed sender, address indexed vault, address adapter, MarketParams marketParams, bool canDeallocate
    );
    event SetCanDeallocateFromIdle(address indexed sender, address indexed vault, bool canDeallocate);
    event SetEthPenalty(address indexed sender, address indexed vault, uint256 newEthPenalty);
    event ClaimEthPenalty(address indexed sender, address indexed vault, uint256 claimed, address receiver);
    event Reallocate(
        address indexed sender, address indexed vault, bytes32 indexed allocateId, bytes32 deallocateId, uint128 assets
    );
    event AllocateFromIdle(address indexed sender, address indexed vault, bytes32 indexed allocateId, uint128 assets);

    /* ERRORS */

    error Unauthorized();
    error AbsoluteCapExceeded();
    error CannotDeallocate();
    error EthTransferFailed();
    error IncorrectEthPenalty();

    /* VIEW */

    /// @dev A Morpho Market V1 market of a vault is keyed by its per-market vault id,
    /// id = keccak256(abi.encode("this/marketParams", adapter, marketParams)), exactly as in the vault's caps.
    function absoluteCap(address vault, bytes32 id) external view returns (uint256);
    function canDeallocate(address vault, bytes32 id) external view returns (bool);
    function canDeallocateFromIdle(address vault) external view returns (bool);
    function ethPenalty(address vault) external view returns (uint256);
    function accruedEthPenalty(address vault) external view returns (uint256);

    /* FUNCTIONS */

    function setAbsoluteCap(address vault, address adapter, MarketParams calldata marketParams, uint256 newAbsoluteCap)
        external;
    function setCanDeallocate(address vault, address adapter, MarketParams calldata marketParams, bool newCanDeallocate)
        external;
    function setCanDeallocateFromIdle(address vault, bool newCanDeallocate) external;
    function setEthPenalty(address vault, uint256 newEthPenalty) external;
    function claimEthPenalty(address vault, address payable receiver) external;
    function reallocate(
        address vault,
        address deallocateAdapter,
        MarketParams calldata deallocateMarketParams,
        address allocateAdapter,
        MarketParams calldata allocateMarketParams,
        uint128 assets
    ) external payable;
    /// @dev Allocates assets from the vault's idle balance.
    function allocate(address vault, address adapter, MarketParams calldata marketParams, uint128 assets)
        external
        payable;
}
