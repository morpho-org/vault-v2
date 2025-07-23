// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Morpho Association
pragma solidity ^0.8.0;

import "../../src/interfaces/IAdapter.sol";
import {IERC20} from "../../src/interfaces/IERC20.sol";
import {IVaultV2} from "../../src/interfaces/IVaultV2.sol";

contract CSMockAdapter is IAdapter {
    address public immutable vault;
    bytes32 public immutable adapterId;
    uint256 public trackedAssets;

    constructor(address _vault) {
        vault = _vault;
        IERC20(IVaultV2(_vault).asset()).approve(_vault, type(uint256).max);
        adapterId = keccak256(abi.encode("this", address(this)));
    }

    function allocate(bytes memory, uint256 assets, bytes4, address)
        external
        returns (bytes32[] memory ids, uint256 interest)
    {
        bytes32[] memory _ids = new bytes32[](1);
        _ids[0] = adapterId;

        interest = trackedAssets / 100;
        trackedAssets += assets + interest;

        return (_ids, interest);
    }

    function deallocate(bytes memory, uint256 assets, bytes4, address)
        external
        returns (bytes32[] memory ids, uint256 interest)
    {
        bytes32[] memory _ids = new bytes32[](1);
        _ids[0] = adapterId;

        interest = trackedAssets / 100;
        trackedAssets += interest;
        trackedAssets -= assets;

        return (_ids, interest);
    }

    function realizeLoss(bytes memory, bytes4, address) external view returns (bytes32[] memory ids, uint256 loss) {
        bytes32[] memory _ids = new bytes32[](1);
        _ids[0] = adapterId;
        loss = allocation();
        return (_ids, loss);
    }

    function allocation() public view returns (uint256) {
        return IVaultV2(vault).allocation(adapterId);
    }
}
