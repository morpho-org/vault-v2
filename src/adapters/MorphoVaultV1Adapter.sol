// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Morpho Association
pragma solidity 0.8.28;

import {IVaultV2} from "../interfaces/IVaultV2.sol";
import {IERC4626} from "../interfaces/IERC4626.sol";
import {IERC20} from "../interfaces/IERC20.sol";
import {IMorphoVaultV1Adapter} from "./interfaces/IMorphoVaultV1Adapter.sol";
import {SafeERC20Lib} from "../libraries/SafeERC20Lib.sol";

/// @dev Designed, developed and audited for Morpho Vaults V1 (V1.0 and V1.1) (also known as MetaMorpho). Integration
/// with other vaults must be carefully assessed from a security standpoint.
/// @dev This adapter must be used with Morpho Vaults V1 that are protected against inflation attacks with an initial
/// deposit. See https://docs.openzeppelin.com/contracts/5.x/erc4626#inflation-attack.
/// @dev Must not be used with a Morpho Vault V1 which has a market with an Irm that can re-enter the parent vault or
/// the adapter.
/// @dev Morpho Vaults V1.1 do not realize bad debt, so Morpho Vaults V2 supplying in them will not realize the
/// corresponding bad debt.
/// @dev Losses that correspond to rounding errors are realizable.
/// @dev Shares of the Morpho Vault V1 cannot be skimmed (unlike any other token).
/// @dev If expectedSupplyAssets reverts for a market of the morphoVaultV1, realAssets will revert and the vault will
/// not be able to accrueInterest.
/// @dev Shouldn't be used alongside another adapter that re-uses the id (abi.encode("this", address(this)).
contract MorphoVaultV1Adapter is IMorphoVaultV1Adapter {
    /* IMMUTABLES */

    address public immutable factory;
    address public immutable parentVault;
    address public immutable morphoVaultV1;
    bytes32 public immutable adapterId;

    /* STORAGE */

    address public skimRecipient;

    /* FUNCTIONS */

    constructor(address _parentVault, address _morphoVaultV1) {
        factory = msg.sender;
        parentVault = _parentVault;
        morphoVaultV1 = _morphoVaultV1;
        adapterId = keccak256(abi.encode("this", address(this)));
        address asset = IVaultV2(_parentVault).asset();
        require(asset == IERC4626(_morphoVaultV1).asset(), AssetMismatch());
        SafeERC20Lib.safeApprove(asset, _parentVault, type(uint256).max);
        SafeERC20Lib.safeApprove(asset, _morphoVaultV1, type(uint256).max);
    }

    function setSkimRecipient(address newSkimRecipient) external {
        require(msg.sender == IVaultV2(parentVault).owner(), NotAuthorized());
        skimRecipient = newSkimRecipient;
        emit SetSkimRecipient(newSkimRecipient);
    }

    /// @dev Skims the adapter's balance of `token` and sends it to `skimRecipient`.
    /// @dev This is useful to handle rewards that the adapter has earned.
    function skim(address token) external {
        require(msg.sender == skimRecipient, NotAuthorized());
        require(token != morphoVaultV1, CannotSkimMorphoVaultV1Shares());
        uint256 balance = IERC20(token).balanceOf(address(this));
        SafeERC20Lib.safeTransfer(token, skimRecipient, balance);
        emit Skim(token, balance);
    }

    /// @dev Does not log anything because the ids (logged in the parent vault) are enough.
    /// @dev Returns the ids of the allocation and the change in allocation.
    function allocate(bytes memory data, uint256 assets, bytes4, address) external returns (bytes32[] memory, int256) {
        require(data.length == 0, InvalidData());
        require(msg.sender == parentVault, NotAuthorized());

        if (assets > 0) IERC4626(morphoVaultV1).deposit(assets, address(this));
        uint256 oldAllocation = allocation();
        uint256 newAllocation = IERC4626(morphoVaultV1).previewRedeem(IERC4626(morphoVaultV1).balanceOf(address(this)));

        // Safe casts because Market V1 bounds the total supply of the underlying token, and allocation is less than the
        // max total assets of the vault.
        return (ids(), int256(newAllocation) - int256(oldAllocation));
    }

    /// @dev Does not log anything because the ids (logged in the parent vault) are enough.
    /// @dev Returns the ids of the deallocation and the change in allocation.
    function deallocate(bytes memory data, uint256 assets, bytes4, address)
        external
        returns (bytes32[] memory, int256)
    {
        require(data.length == 0, InvalidData());
        require(msg.sender == parentVault, NotAuthorized());

        if (assets > 0) IERC4626(morphoVaultV1).withdraw(assets, address(this), address(this));
        uint256 oldAllocation = allocation();
        uint256 newAllocation = IERC4626(morphoVaultV1).previewRedeem(IERC4626(morphoVaultV1).balanceOf(address(this)));

        // Safe casts because Market V1 bounds the total supply of the underlying token, and allocation is less than the
        // max total assets of the vault.
        return (ids(), int256(newAllocation) - int256(oldAllocation));
    }

    /// @dev Returns adapter's ids.
    function ids() public view returns (bytes32[] memory) {
        bytes32[] memory ids_ = new bytes32[](1);
        ids_[0] = adapterId;
        return ids_;
    }

    function allocation() public view returns (uint256) {
        return IVaultV2(parentVault).allocation(adapterId);
    }

    function realAssets() external view returns (uint256) {
        return allocation() != 0
            ? IERC4626(morphoVaultV1).previewRedeem(IERC4626(morphoVaultV1).balanceOf(address(this)))
            : 0;
    }
}
