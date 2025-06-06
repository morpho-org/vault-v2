// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.28;

import {IVaultV2} from "../interfaces/IVaultV2.sol";
import {IERC4626} from "../interfaces/IERC4626.sol";
import {IERC20} from "../interfaces/IERC20.sol";
import {IMetaMorphoAdapter} from "./interfaces/IMetaMorphoAdapter.sol";
import {SafeERC20Lib} from "../libraries/SafeERC20Lib.sol";
import {MathLib} from "../libraries/MathLib.sol";

/// @dev Designed, developped and audited for MetaMorpho Vaults (v1.0 and v1.1). Integration with other vaults must be
/// carefully assessed from a security standpoint.
/// @dev MetaMorpho V1.1 vaults do not realize bad debt, so vaults V2 supplying in them will not realize the
/// corresponding bad debt.
contract MetaMorphoAdapter is IMetaMorphoAdapter {
    using MathLib for uint256;

    /* IMMUTABLES */

    address public immutable parentVault;
    address public immutable metaMorpho;

    /* STORAGE */

    address public skimRecipient;
    uint256 public assetsInMetaMorpho;
    uint256 public realizableLoss;

    /* FUNCTIONS */

    constructor(address _parentVault, address _metaMorpho) {
        parentVault = _parentVault;
        metaMorpho = _metaMorpho;
        address asset = IVaultV2(_parentVault).asset();
        require(asset == IERC4626(_metaMorpho).asset(), WrongAsset());
        SafeERC20Lib.safeApprove(asset, _parentVault, type(uint256).max);
        SafeERC20Lib.safeApprove(asset, _metaMorpho, type(uint256).max);
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
        require(token != metaMorpho, CannotSkimMetaMorphoShares());
        uint256 balance = IERC20(token).balanceOf(address(this));
        SafeERC20Lib.safeTransfer(token, skimRecipient, balance);
        emit Skim(token, balance);
    }

    /// @dev Does not log anything because the ids (logged in the parent vault) are enough.
    /// @dev Returns the ids of the allocation and the potential loss.
    function allocate(bytes memory data, uint256 assets) external returns (bytes32[] memory, uint256) {
        require(data.length == 0, InvalidData());
        require(msg.sender == parentVault, NotAuthorized());

        // To accrue interest only one time.
        IERC4626(metaMorpho).deposit(0, address(this));
        uint256 newAssetsInMetaMorpho =
            IERC4626(metaMorpho).previewRedeem(IERC4626(metaMorpho).balanceOf(address(this)));
        realizableLoss += assetsInMetaMorpho.zeroFloorSub(newAssetsInMetaMorpho);
        uint256 interest = newAssetsInMetaMorpho.zeroFloorSub(assetsInMetaMorpho);

        IERC4626(metaMorpho).deposit(assets, address(this));
        assetsInMetaMorpho = IERC4626(metaMorpho).previewRedeem(IERC4626(metaMorpho).balanceOf(address(this)));

        return (ids(), interest);
    }

    /// @dev Does not log anything because the ids (logged in the parent vault) are enough.
    /// @dev Returns the ids of the deallocation and the potential loss.
    function deallocate(bytes memory data, uint256 assets) external returns (bytes32[] memory, uint256) {
        require(data.length == 0, InvalidData());
        require(msg.sender == parentVault, NotAuthorized());

        // To accrue interest only one time.
        IERC4626(metaMorpho).deposit(0, address(this));

        uint256 newAssetsInMetaMorpho =
            IERC4626(metaMorpho).previewRedeem(IERC4626(metaMorpho).balanceOf(address(this)));
        realizableLoss += assetsInMetaMorpho.zeroFloorSub(newAssetsInMetaMorpho);
        uint256 interest = newAssetsInMetaMorpho.zeroFloorSub(assetsInMetaMorpho);

        IERC4626(metaMorpho).withdraw(assets, address(this), address(this));
        assetsInMetaMorpho = IERC4626(metaMorpho).previewRedeem(IERC4626(metaMorpho).balanceOf(address(this)));

        return (ids(), interest);
    }

    function realizeLoss(bytes memory data) external returns (bytes32[] memory, uint256) {
        require(msg.sender == parentVault, NotAuthorized());
        require(data.length == 0, InvalidData());

        uint256 newAssetsInMetaMorpho =
            IERC4626(metaMorpho).previewRedeem(IERC4626(metaMorpho).balanceOf(address(this)));
        uint256 loss = realizableLoss + assetsInMetaMorpho.zeroFloorSub(newAssetsInMetaMorpho);
        realizableLoss = 0;
        assetsInMetaMorpho = newAssetsInMetaMorpho;

        return (ids(), loss);
    }

    /// @dev Returns adapter's ids.
    function ids() internal view returns (bytes32[] memory) {
        bytes32[] memory ids_ = new bytes32[](1);
        ids_[0] = keccak256(abi.encode("adapter", address(this)));
        return ids_;
    }
}
