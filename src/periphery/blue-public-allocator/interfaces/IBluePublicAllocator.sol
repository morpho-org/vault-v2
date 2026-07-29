// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Morpho Association
pragma solidity >=0.8.0;

import {MarketParams} from "../../../../lib/morpho-blue/src/interfaces/IMorpho.sol";

struct VaultData {
    bool canAllocateFromIdle;
    uint120 nativePenalty;
    uint120 accruedNativePenalty;
}

// forgefmt: disable-start
interface IBluePublicAllocator {

    /* EVENTS */

    event SetAbsoluteCap(address indexed sender, address indexed vault, address adapter, MarketParams marketParams, uint256 absoluteCap);
    event SetCanDeallocate(address indexed sender, address indexed vault, address adapter, MarketParams marketParams, bool canDeallocate);
    event SetCanAllocateFromIdle(address indexed sender, address indexed vault, bool canDeallocate);
    event SetIsActiveAdapter(address indexed sender, address indexed vault, address indexed adapter, bool isActiveAdapter);
    event SetNativePenalty(address indexed sender, address indexed vault, uint256 newNativePenalty);
    event ClaimNativePenalty(address indexed sender, address indexed vault, uint256 claimed, address indexed receiver);
    event Reallocate(address sender, address indexed vault, address deallocateAdapter, bytes32 indexed deallocateId, address allocateAdapter, bytes32 indexed allocateId, uint128 assets, uint256 value);
    event AllocateFromIdle(address indexed sender, address indexed vault, address adapter, bytes32 indexed allocateId, uint128 assets, uint256 value);

    /* ERRORS */

    error Unauthorized();
    error AbsoluteCapExceeded();
    error CannotDeallocate();
    error NativeTransferFailed();
    error IncorrectNativePenalty();
    error InactiveAdapter();
    error CastOverflow();

    /* VIEW */

    function absoluteCap(address vault, bytes32 id) external view returns (uint256);
    function canDeallocate(address vault, bytes32 id) external view returns (bool);
    function isActiveAdapter(address vault, address adapter) external view returns (bool);
    function vaultData(address vault) external view returns (bool canAllocateFromIdle, uint120 nativePenalty, uint120 accruedNativePenalty);

    /* FUNCTIONS */

    function multicall(bytes[] calldata data) external;
    function setIsActiveAdapter(address vault, address adapter, bool newIsActiveAdapter) external;
    function setAbsoluteCap(address vault, address adapter, MarketParams calldata marketParams, uint256 newAbsoluteCap) external;
    function setCanDeallocate(address vault, address adapter, MarketParams calldata marketParams, bool newCanDeallocate) external;
    function setCanAllocateFromIdle(address vault, bool newCanDeallocate) external;
    function setNativePenalty(address vault, uint256 newNativePenalty) external;
    function claimNativePenalty(address vault, address payable receiver) external;
    function reallocate(address vault, address deallocateAdapter, MarketParams calldata deallocateMarketParams, address allocateAdapter, MarketParams calldata allocateMarketParams, uint128 assets) external payable;
    function allocateFromIdle(address vault, address adapter, MarketParams calldata marketParams, uint128 assets) external payable;
}
// forgefmt: disable-end
