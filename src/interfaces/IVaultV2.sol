// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity >=0.5.0;

import {IERC20} from "./IERC20.sol";
import {IERC4626} from "./IERC4626.sol";
import {IPermissionedToken} from "./IPermissionedToken.sol";

struct Caps {
    uint256 allocation;
    uint128 absoluteCap;
    uint128 relativeCap;
}

interface IVaultV2 is IERC4626, IPermissionedToken {
    // Multicall
    function multicall(bytes[] memory data) external;

    // ERC-2612 (Permit)
    function permit(address owner, address spender, uint256 shares, uint256 deadline, uint8 v, bytes32 r, bytes32 s)
        external;
    function nonces(address owner) external view returns (uint256);
    function DOMAIN_SEPARATOR() external view returns (bytes32);

    // State variables
    function owner() external view returns (address);
    function curator() external view returns (address);
    function isSentinel(address account) external view returns (bool);
    function isAllocator(address account) external view returns (bool);
    function isAdapter(address account) external view returns (bool);
    function performanceFee() external view returns (uint96);
    function managementFee() external view returns (uint96);
    function performanceFeeRecipient() external view returns (address);
    function managementFeeRecipient() external view returns (address);
    function forceDeallocatePenalty(address adapter) external view returns (uint256);
    function vic() external view returns (address);
    function allocation(bytes32 id) external view returns (uint256);
    function lastUpdate() external view returns (uint64);
    function enterBlocked() external view returns (bool);
    function absoluteCap(bytes32 id) external view returns (uint256);
    function relativeCap(bytes32 id) external view returns (uint256);
    function executableAt(bytes memory data) external view returns (uint256);
    function timelock(bytes4 selector) external view returns (uint256);
    function liquidityAdapter() external view returns (address);
    function liquidityData() external view returns (bytes memory);
    function sharesGate() external view returns (address);
    function receiveAssetsGate() external view returns (address);
    function sendAssetsGate() external view returns (address);
    function totalAllocation() external view returns (uint256);

    // Owner actions
    function setOwner(address newOwner) external;
    function setSharesGate(address newSharesGate) external;
    function setReceiveAssetsGate(address newReceiveAssetsGate) external;
    function setSendAssetsGate(address newSendAssetsGate) external;
    function setCurator(address newCurator) external;
    function setIsSentinel(address account, bool isSentinel) external;
    function setName(string memory newName) external;
    function setSymbol(string memory newSymbol) external;

    // Curator actions
    function setVic(address newVic) external;
    function increaseTimelock(bytes4 selector, uint256 newDuration) external;
    function decreaseTimelock(bytes4 selector, uint256 newDuration) external;
    function abdicateSubmit(bytes4 selector) external;
    function setIsAllocator(address account, bool newIsAllocator) external;
    function setIsAdapter(address account, bool newIsAdapter) external;
    function setForceDeallocatePenalty(address adapter, uint256 newForceDeallocatePenalty) external;
    function increaseAbsoluteCap(bytes memory idData, uint256 newAbsoluteCap) external;
    function increaseRelativeCap(bytes memory idData, uint256 newRelativeCap) external;
    function decreaseAbsoluteCap(bytes memory idData, uint256 newAbsoluteCap) external;
    function decreaseRelativeCap(bytes memory idData, uint256 newRelativeCap) external;
    function setPerformanceFee(uint256 newPerformanceFee) external;
    function setManagementFee(uint256 newManagementFee) external;
    function setPerformanceFeeRecipient(address newPerformanceFeeRecipient) external;
    function setManagementFeeRecipient(address newManagementFeeRecipient) external;

    // Allocator actions
    function allocate(address adapter, bytes memory data, uint256 assets) external;
    function deallocate(address adapter, bytes memory data, uint256 assets) external;
    function setLiquidityMarket(address newLiquidityAdapter, bytes memory newLiquidityData) external;

    // Exchange rate
    function accrueInterest() external;
    function accrueInterestView()
        external
        view
        returns (uint256 newTotalAssets, uint256 performanceFeeShares, uint256 managementFeeShares);

    // Timelocks
    function submit(bytes memory data) external;
    function revoke(bytes memory data) external;

    // Force reallocate to idle
    function forceDeallocate(address adapter, bytes memory data, uint256 assets, address onBehalf)
        external
        returns (uint256 withdrawnShares);

    // Permissioned token
    function canSend(address account) external view returns (bool);
    function canReceive(address account) external view returns (bool);
}
