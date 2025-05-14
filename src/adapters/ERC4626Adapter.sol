// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.28;

import {IVaultV2} from "../interfaces/IVaultV2.sol";
import {IERC4626} from "../interfaces/IERC4626.sol";
import {IERC20} from "../interfaces/IERC20.sol";
import {IERC4626Adapter} from "./interfaces/IERC4626Adapter.sol";
import {SafeERC20Lib} from "../libraries/SafeERC20Lib.sol";

/// Vaults should transfer exactly the input in deposit and withdraw.
contract ERC4626Adapter is IERC4626Adapter {
    /* IMMUTABLES */

    address public immutable parentVault;
    address public immutable vault;

    /* STORAGE */

    address public skimRecipient;

    /* FUNCTIONS */

    constructor(address _parentVault, address _vault) {
        parentVault = _parentVault;
        vault = _vault;
        SafeERC20Lib.safeApprove(IVaultV2(_parentVault).asset(), _parentVault, type(uint256).max);
        SafeERC20Lib.safeApprove(IVaultV2(_parentVault).asset(), _vault, type(uint256).max);
    }

    function setSkimRecipient(address newSkimRecipient) external {
        require(msg.sender == IVaultV2(parentVault).owner(), NotAuthorized());
        skimRecipient = newSkimRecipient;
        emit SetSkimRecipient(newSkimRecipient);
    }

    function skim(address token) external {
        require(msg.sender == skimRecipient, NotAuthorized());
        require(token != vault, CannotSkimVault());
        uint256 balance = IERC20(token).balanceOf(address(this));
        SafeERC20Lib.safeTransfer(token, skimRecipient, balance);
        emit Skim(token, balance);
    }

    /// @dev Does not log anything because the ids (logged in the parent vault) are enough.
    function allocate(bytes memory data, uint256 assets) external returns (bytes32[] memory) {
        require(data.length == 0, InvalidData());
        require(msg.sender == parentVault, NotAuthorized());

        IERC4626(vault).deposit(assets, address(this));

        return ids();
    }

    /// @dev Does not log anything because the ids (logged in the parent vault) are enough.
    function deallocate(bytes memory data, uint256 assets) external returns (bytes32[] memory) {
        require(data.length == 0, InvalidData());
        require(msg.sender == parentVault, NotAuthorized());

        IERC4626(vault).withdraw(assets, address(this), address(this));

        return ids();
    }

    function ids() internal view returns (bytes32[] memory) {
        bytes32[] memory ids_ = new bytes32[](1);
        ids_[0] = keccak256(abi.encode("adapter", address(this)));
        return ids_;
    }
}
