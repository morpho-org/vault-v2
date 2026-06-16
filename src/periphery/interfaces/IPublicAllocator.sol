// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Morpho Association
pragma solidity >=0.5.0;

interface IPublicAllocator {
    /* EVENTS */

    event SetCanAllocate(address indexed sender, address indexed vault, address adapter, bytes data, bool canAllocate);
    event SetFee(address indexed sender, address indexed vault, uint256 newFee);
    event ClaimFee(address indexed sender, address indexed vault, uint256 amount, address indexed recipient);
    event Reallocate(
        address indexed sender,
        address indexed vault,
        bytes32 indexed allocateKey,
        bytes32 deallocateKey,
        uint128 assets
    );

    /* ERRORS */

    error Unauthorized();
    error CannotAllocate();
    error IncorrectFee();
    error FeeTransferFailed();

    /* VIEW */

    /// @dev An (adapter, data) pair of a vault, exactly as in VaultV2.allocate/deallocate, is keyed by
    /// key = keccak256(abi.encode(adapter, data)).
    function canAllocate(address vault, bytes32 key) external view returns (bool);
    function fee(address vault) external view returns (uint256);
    function accruedFee(address vault) external view returns (uint256);

    /* FUNCTIONS */

    function setCanAllocate(address vault, address adapter, bytes calldata data, bool newCanAllocate) external;
    function setFee(address vault, uint256 newFee) external;
    function claimFee(address vault, address payable recipient) external;
    function reallocate(
        address vault,
        address deallocateAdapter,
        bytes calldata deallocateData,
        address allocateAdapter,
        bytes calldata allocateData,
        uint128 amount
    ) external payable;
}
