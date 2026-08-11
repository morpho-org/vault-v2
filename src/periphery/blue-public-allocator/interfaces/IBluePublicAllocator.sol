// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Morpho Association
pragma solidity >=0.8.0;

import {MarketParams} from "../../../../lib/morpho-blue/src/interfaces/IMorpho.sol";

struct VaultData {
    bool canPullFromIdle;
    uint64 penalty;
}

// forgefmt: disable-start
interface IBluePublicAllocator {

    /* EVENTS */

    event SetAbsoluteCap(address indexed sender, address indexed vault, address adapter, MarketParams marketParams, uint256 absoluteCap);
    event SetCanPullFromMarket(address indexed sender, address indexed vault, address adapter, MarketParams marketParams, bool canPullFromMarket);
    event SetCanPullFromIdle(address indexed sender, address indexed vault, bool canPullFromIdle);
    event SetIsActiveAdapter(address indexed sender, address indexed vault, address indexed adapter, bool isActiveAdapter);
    event SetPenalty(address indexed sender, address indexed vault, uint256 newPenalty);
    event Reallocate(address sender, address indexed vault, address deallocateAdapter, bytes32 indexed deallocateId, address allocateAdapter, bytes32 indexed allocateId, uint128 assets, uint256 penaltyAssets);
    event AllocateFromIdle(address indexed sender, address indexed vault, address adapter, bytes32 indexed allocateId, uint128 assets, uint256 penaltyAssets);

    /* ERRORS */

    error Unauthorized();
    error AbsoluteCapExceeded();
    error CannotPullFromMarket();
    error CannotPullFromIdle();
    error InactiveAdapter();
    error PenaltyTooHigh();

    /* VIEW */

    function absoluteCap(address vault, bytes32 id) external view returns (uint256);
    function canPullFromMarket(address vault, bytes32 id) external view returns (bool);
    function isActiveAdapter(address vault, address adapter) external view returns (bool);
    function vaultData(address vault) external view returns (bool canPullFromIdle, uint64 penalty);

    /* FUNCTIONS */

    function multicall(bytes[] calldata data) external;
    function setIsActiveAdapter(address vault, address adapter, bool newIsActiveAdapter) external;
    function setAbsoluteCap(address vault, address adapter, MarketParams calldata marketParams, uint256 newAbsoluteCap) external;
    function setCanPullFromMarket(address vault, address adapter, MarketParams calldata marketParams, bool newCanPullFromMarket) external;
    function setCanPullFromIdle(address vault, bool newCanPullFromIdle) external;
    function setPenalty(address vault, uint256 newPenalty) external;
    function reallocate(address vault, address deallocateAdapter, MarketParams calldata deallocateMarketParams, address allocateAdapter, MarketParams calldata allocateMarketParams, uint128 assets) external;
    function allocateFromIdle(address vault, address adapter, MarketParams calldata marketParams, uint128 assets) external;
}
// forgefmt: disable-end
