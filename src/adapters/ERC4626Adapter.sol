// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.28;

import {IVaultV2} from "../interfaces/IVaultV2.sol";
import {IAdapter} from "../interfaces/IAdapter.sol";
import {IERC4626} from "../interfaces/IERC4626.sol";
import {IERC20} from "../interfaces/IERC20.sol";
import {SafeERC20Lib} from "../libraries/SafeERC20Lib.sol";
import {MathLib} from "../libraries/MathLib.sol";

/// Vaults should transfer exactly the input in deposit and withdraw.
contract ERC4626Adapter is IAdapter {
    using MathLib for uint256;

    /* IMMUTABLES */

    address public immutable parentVault;
    address public immutable vault;

    /* STORAGE */

    address public skimRecipient;
    uint256 public assetsInVaultIfNoLoss;

    /* EVENTS */

    event SetSkimRecipient(address indexed newSkimRecipient);
    event Skim(address indexed token, uint256 assets);

    /* ERRORS */

    error NotAuthorized();
    error InvalidData();
    error CannotSkimVault();

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
        uint256 assetsInVault = IERC4626(vault).previewRedeem(IERC4626(vault).balanceOf(address(this)));
        assetsInVaultIfNoLoss = max(assetsInVaultIfNoLoss + assets, assetsInVault);

        return ids();
    }

    /// @dev Does not log anything because the ids (logged in the parent vault) are enough.
    function deallocate(bytes memory data, uint256 assets) external returns (bytes32[] memory) {
        require(data.length == 0, InvalidData());
        require(msg.sender == parentVault, NotAuthorized());

        IERC4626(vault).withdraw(assets, address(this), address(this));
        uint256 assetsInVault = IERC4626(vault).previewRedeem(IERC4626(vault).balanceOf(address(this)));
        assetsInVaultIfNoLoss = max(assetsInVaultIfNoLoss - assets, assetsInVault);

        return ids();
    }

    function realiseLoss(bytes memory) external returns (uint256, bytes32[] memory) {
        require(msg.sender == parentVault, NotAuthorized());
        uint256 assetsInVault = IERC4626(vault).previewRedeem(IERC4626(vault).balanceOf(address(this)));
        uint256 loss = assetsInVaultIfNoLoss.zeroFloorSub(assetsInVault);
        assetsInVaultIfNoLoss = assetsInVault;
        return (loss, ids());
    }

    function ids() internal view returns (bytes32[] memory) {
        bytes32[] memory ids_ = new bytes32[](1);
        ids_[0] = keccak256(abi.encode("adapter", address(this)));
        return ids_;
    }
}

function max(uint256 a, uint256 b) pure returns (uint256) {
    return a > b ? a : b;
}
