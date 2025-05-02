// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.28;

import {IVaultV2} from "../interfaces/IVaultV2.sol";
import {IERC4626} from "../interfaces/IERC4626.sol";
import {IERC20} from "../interfaces/IERC20.sol";
import {AdapterEventsLib} from "./AdapterEventsLib.sol";
import {SafeERC20Lib} from "../libraries/SafeERC20Lib.sol";

contract ERC4626Adapter {
    /* IMMUTABLES */

    address public immutable parentVault;
    address public immutable asset;

    /* STORAGE */

    address public skimRecipient;

    /* FUNCTIONS */

    constructor(address _parentVault) {
        parentVault = _parentVault;
        asset = IVaultV2(_parentVault).asset();
        SafeERC20Lib.safeApprove(IVaultV2(_parentVault).asset(), _parentVault, type(uint256).max);
    }

    function setSkimRecipient(address newSkimRecipient) external {
        require(msg.sender == IVaultV2(parentVault).owner(), "not authorized");
        skimRecipient = newSkimRecipient;
        emit AdapterEventsLib.SetSkimRecipient(newSkimRecipient);
    }

    /// @dev Does not log anything because the ids (logged in the parent vault) are enough.
    function allocateIn(bytes memory data, uint256 assets) external returns (bytes32[] memory) {
        require(msg.sender == parentVault, "not authorized");
        (address vault) = abi.decode(data, (address));

        IERC20(asset).approve(vault, assets);
        IERC4626(vault).deposit(assets, address(this));

        bytes32[] memory ids = new bytes32[](1);
        ids[0] = keccak256(abi.encode("vault", vault));
        return ids;
    }

    /// @dev Does not log anything because the ids (logged in the parent vault) are enough.
    function allocateOut(bytes memory data, uint256 assets) external returns (bytes32[] memory) {
        require(msg.sender == parentVault, "not authorized");
        (address vault) = abi.decode(data, (address));

        IERC4626(vault).withdraw(assets, address(this), address(this));

        bytes32[] memory ids = new bytes32[](1);
        ids[0] = keccak256(abi.encode("vault", vault));
        return ids;
    }

    function skim(address token) external {
        uint256 balance = IERC20(token).balanceOf(address(this));
        SafeERC20Lib.safeTransfer(token, skimRecipient, balance);

        emit AdapterEventsLib.Skim(token, balance);
    }
}
