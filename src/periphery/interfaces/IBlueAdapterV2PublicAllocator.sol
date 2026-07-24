// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Morpho Association
pragma solidity >=0.5.0;

import {MarketParams} from "../../../lib/morpho-blue/src/interfaces/IMorpho.sol";

// forgefmt: disable-start

interface IBlueAdapterV2PublicAllocator {
    /* EVENTS */

    event SetAbsoluteCap(address indexed sender, address indexed vault, address adapter, MarketParams marketParams, uint256 absoluteCap);
    event SetCanDeallocate(address indexed sender, address indexed vault, address adapter, MarketParams marketParams, bool canDeallocate);
    event SetCanDeallocateFromIdle(address indexed sender, address indexed vault, bool canDeallocate);
    event SetNativePenalty(address indexed sender, address indexed vault, uint256 newNativePenalty);
    event ClaimNativePenalty(address indexed sender, address indexed vault, uint256 claimed, address receiver);
    event Reallocate(address sender, address indexed vault, bytes32 indexed allocateId, bytes32 indexed deallocateId, uint128 assets, uint256 value);
    event AllocateFromIdle(address indexed sender, address indexed vault, bytes32 indexed allocateId, uint128 assets, uint256 value);

    /* ERRORS */

    error Unauthorized();
    error AbsoluteCapExceeded();
    error CannotDeallocate();
    error NativeTransferFailed();
    error IncorrectNativePenalty();
    error NotBlueAdapter();

    /* VIEW */

    function adapterFactory() external view returns (address);
    function absoluteCap(address vault, bytes32 id) external view returns (uint256);
    function canDeallocate(address vault, bytes32 id) external view returns (bool);
    function canDeallocateFromIdle(address vault) external view returns (bool);
    function nativePenalty(address vault) external view returns (uint256);
    function accruedNativePenalty(address vault) external view returns (uint256);

    /* FUNCTIONS */

    function setAbsoluteCap(address vault, address adapter, MarketParams calldata marketParams, uint256 newAbsoluteCap) external;
    function setCanDeallocate(address vault, address adapter, MarketParams calldata marketParams, bool newCanDeallocate) external;
    function setCanDeallocateFromIdle(address vault, bool newCanDeallocate) external;
    function setNativePenalty(address vault, uint256 newNativePenalty) external;
    function claimNativePenalty(address vault, address payable receiver) external;
    function reallocate(address vault, address adapter, MarketParams calldata deallocateMarketParams, MarketParams calldata allocateMarketParams, uint128 assets) external payable;
    function allocateFromIdle(address vault, address adapter, MarketParams calldata marketParams, uint128 assets) external payable;
}

// forgefmt: disable-end
