// SPDX-License-Identifier: GPL-2.0-or-later
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

    uint256 public loss;
    uint256 public interest;

    constructor(address _vault) {
        vault = _vault;
        IERC20(IVaultV2(_vault).asset()).approve(_vault, type(uint256).max);
    }

    function setLoss(uint256 _loss) external {
        loss = _loss;
    }

    function setInterest(uint256 _interest) external {
        interest = _interest;
    }

    function allocate(bytes memory data, uint256 assets) external returns (bytes32[] memory, int256) {
        recordedAllocateData = data;
        recordedAllocateAssets = assets;
        return (ids(), int256(assets) - int256(loss) + int256(interest));
    }

    function deallocate(bytes memory data, uint256 assets) external returns (bytes32[] memory, int256) {
        recordedDeallocateData = data;
        recordedDeallocateAssets = assets;
        return (ids(), -int256(assets) - int256(loss) + int256(interest));
    }

    function ids() public pure returns (bytes32[] memory) {
        bytes32[] memory _ids = new bytes32[](2);
        _ids[0] = keccak256("id-0");
        _ids[1] = keccak256("id-1");
        return _ids;
    }
}
