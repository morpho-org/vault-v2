// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.28;

import {IVaultV2} from "../interfaces/IVaultV2.sol";
import {IERC20} from "../interfaces/IERC20.sol";
import {IAaveV3Adapter} from "./interfaces/IAaveV3Adapter.sol";
import {IAaveV3AToken} from "../interfaces/IAaveV3AToken.sol";
import {IAaveV3Pool} from "../interfaces/IAaveV3Pool.sol";
import {SafeERC20Lib} from "../libraries/SafeERC20Lib.sol";

/// @title AaveV3Adapter
/// @notice Adapter for integrating Aave V3 lending pool with Morpho Vault V2
/// @dev This adapter supplies assets to Aave V3 and tracks the position via aToken balance.
/// @dev aTokens auto-compound, so realAssets() = aToken.balanceOf(adapter).
/// @dev Must not be used if aToken can re-enter the vault or adapter.
/// @dev Shares of the aToken cannot be skimmed (unlike any other token).
/// @dev Shouldn't be used alongside another adapter that re-uses the id (abi.encode("this", address(this)).
contract AaveV3Adapter is IAaveV3Adapter {
    /* IMMUTABLES */

    address public immutable factory;
    address public immutable parentVault;
    address public immutable asset;
    address public immutable aavePool;
    address public immutable aToken;
    bytes32 public immutable adapterId;

    /* STORAGE */

    address public skimRecipient;

    /* FUNCTIONS */

    constructor(address _parentVault, address _aavePool, address _aToken) {
        factory = msg.sender;
        parentVault = _parentVault;
        aavePool = _aavePool;
        aToken = _aToken;
        asset = IVaultV2(_parentVault).asset();
        require(IAaveV3AToken(_aToken).UNDERLYING_ASSET_ADDRESS() == asset, AssetMismatch());
        adapterId = keccak256(abi.encode("this", address(this)));
        SafeERC20Lib.safeApprove(asset, _parentVault, type(uint256).max);
        SafeERC20Lib.safeApprove(asset, _aavePool, type(uint256).max);
    }

    function setSkimRecipient(address newSkimRecipient) external {
        require(msg.sender == IVaultV2(parentVault).owner(), NotAuthorized());
        skimRecipient = newSkimRecipient;
        emit SetSkimRecipient(newSkimRecipient);
    }

    /// @dev Skims the adapter's balance of `token` and sends it to `skimRecipient`.
    /// @dev This is useful to handle rewards (e.g., AAVE tokens) that the adapter has earned.
    function skim(address token) external {
        require(msg.sender == skimRecipient, NotAuthorized());
        require(token != aToken, CannotSkimAToken());
        uint256 balance = IERC20(token).balanceOf(address(this));
        SafeERC20Lib.safeTransfer(token, skimRecipient, balance);
        emit Skim(token, balance);
    }

    /// @dev Does not log anything because the ids (logged in the parent vault) are enough.
    /// @dev Returns the ids of the allocation and the change in allocation.
    function allocate(bytes memory data, uint256 assets, bytes4, address) external returns (bytes32[] memory, int256) {
        require(data.length == 0, InvalidData());
        require(msg.sender == parentVault, NotAuthorized());

        if (assets > 0) {
            IAaveV3Pool(aavePool).supply(asset, assets, address(this), 0);
        }

        uint256 oldAllocation = allocation();
        uint256 newAllocation = IERC20(aToken).balanceOf(address(this));

        // safe cast: aToken balance bounded by total supply
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

        if (assets > 0) {
            IAaveV3Pool(aavePool).withdraw(asset, assets, address(this));
        }

        uint256 oldAllocation = allocation();
        uint256 newAllocation = IERC20(aToken).balanceOf(address(this));

        // safe cast: aToken balance bounded by total supply
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

    /// @dev Returns the current value of assets in Aave V3.
    /// @dev aToken balance represents supplied assets + accrued interest.
    function realAssets() external view returns (uint256) {
        return allocation() != 0 ? IERC20(aToken).balanceOf(address(this)) : 0;
    }
}
