// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Morpho Association
pragma solidity ^0.8.0;

import {IAdapter} from "../../src/interfaces/IAdapter.sol";
import {IVaultV2} from "../../src/interfaces/IVaultV2.sol";
import {IERC20} from "../../src/interfaces/IERC20.sol";

contract AdapterMock is IAdapter {
    address public immutable vault;

    bytes public recordedAllocateData;
    uint256 public recordedAllocateAssets;

    bytes public recordedDeallocateData;
    uint256 public recordedDeallocateAssets;

    address public recordedSender;

    constructor(address _vault) {
        vault = _vault;
        IERC20(IVaultV2(_vault).asset()).approve(_vault, type(uint256).max);
    }

    function allocate(bytes memory data, uint256 assets, address sender) external returns (bytes32[] memory, uint256) {
        recordedAllocateData = data;
        recordedAllocateAssets = assets;
        recordedSender = sender;
        return (ids(), 0);
    }

    function deallocate(bytes memory data, uint256 assets, address sender)
        external
        returns (bytes32[] memory, uint256)
    {
        recordedDeallocateData = data;
        recordedDeallocateAssets = assets;
        recordedSender = sender;
        return (ids(), 0);
    }

    function realizeLoss(bytes memory, address sender) external returns (bytes32[] memory, uint256) {
        recordedSender = sender;
        return (ids(), 0);
    }

    function ids() internal pure returns (bytes32[] memory) {
        bytes32[] memory _ids = new bytes32[](2);
        _ids[0] = keccak256("id-0");
        _ids[1] = keccak256("id-1");
        return _ids;
    }
}
