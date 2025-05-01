// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.28;

import {IVaultV2} from "../interfaces/IVaultV2.sol";
import {IERC4626} from "../interfaces/IERC4626.sol";
import {IERC20} from "../interfaces/IERC20.sol";
import {SafeERC20Lib} from "../libraries/SafeERC20Lib.sol";

contract ERC4626Adapter {
    address public immutable parentVault;
    address public immutable asset;

    constructor(address _parentVault) {
        parentVault = _parentVault;
        SafeERC20Lib.safeApprove(IVaultV2(_parentVault).asset(), _parentVault, type(uint256).max);
    }

    function allocateIn(bytes memory data, uint256 assets) external returns (bytes32[] memory) {
        require(msg.sender == parentVault, "not authorized");
        (address vault) = abi.decode(data, (address));

        IERC20(asset).approve(vault, assets);
        IERC4626(vault).deposit(assets, address(this));

        bytes32[] memory ids = new bytes32[](1);
        ids[0] = keccak256(abi.encode("vault", vault));
        return ids;
    }

    function allocateOut(bytes memory data, uint256 assets) external returns (bytes32[] memory) {
        require(msg.sender == parentVault, "not authorized");
        (address vault) = abi.decode(data, (address));

        IERC4626(vault).withdraw(assets, address(this), address(this));

        bytes32[] memory ids = new bytes32[](1);
        ids[0] = keccak256(abi.encode("vault", vault));
        return ids;
    }
}

contract ERC4626AdapterFactory {
    /* STORAGE */

    mapping(address => address) adapter;

    /* EVENTS */

    event CreateERC4626Adapter(address indexed parentVault, address indexed erc4626Adapter);

    function createERC4626Adapter(address _parentVault) external returns (address) {
        address erc4626Adapter = address(new ERC4626Adapter(_parentVault));
        adapter[_parentVault] = erc4626Adapter;
        emit CreateERC4626Adapter(_parentVault, erc4626Adapter);
        return erc4626Adapter;
    }
}
