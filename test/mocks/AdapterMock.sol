// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Morpho Association
pragma solidity ^0.8.0;

import {IAdapter} from "../../src/interfaces/IAdapter.sol";
import {IVaultV2} from "../../src/interfaces/IVaultV2.sol";
import {IERC20} from "../../src/interfaces/IERC20.sol";

contract AdapterMock is IAdapter {
    address public immutable vault;

    bytes32[] public _ids;
    uint256 public interest;
    uint256 public totalAssets;

    bytes public recordedAllocateData;
    uint256 public recordedAllocateAssets;

    bytes public recordedDeallocateData;
    uint256 public recordedDeallocateAssets;

    bytes4 public recordedSelector;
    address public recordedSender;

    constructor(address _vault) {
        vault = _vault;
        if (_vault != address(0)) {
            IERC20(IVaultV2(_vault).asset()).approve(_vault, type(uint256).max);
        }

        _ids.push(keccak256("id-0"));
        _ids.push(keccak256("id-1"));
    }

    function setInterest(uint256 _interest) external {
        interest = _interest;
    }

    function allocate(bytes memory data, uint256 assets, bytes4 selector, address sender)
        external
        returns (bytes32[] memory, int256)
    {
        recordedAllocateData = data;
        recordedAllocateAssets = assets;
        recordedSelector = selector;
        recordedSender = sender;
        return (ids(), int256(assets + interest));
    }

    function deallocate(bytes memory data, uint256 assets, bytes4 selector, address sender)
        external
        returns (bytes32[] memory, int256)
    {
        recordedDeallocateData = data;
        recordedDeallocateAssets = assets;
        recordedSelector = selector;
        recordedSender = sender;
        return (ids(), -int256(assets) + int256(interest));
    }

    function ids() internal view returns (bytes32[] memory) {
        return _ids;
    }

    function totalAssetsNoLoss() external pure returns (uint256) {
        return 0;
    }

    function setTotalAssets(uint256 _totalAssets) external {
        totalAssets = _totalAssets;
    }
}
