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
    uint256 public realisableLoss;
    uint256 public assetsInVault;

    /* EVENTS */

    event SetSkimRecipient(address indexed newSkimRecipient);
    event Skim(address indexed token, uint256 amount);

    /* ERRORS */

    error NotAuthorized();
    error InvalidData();
    error CantSkimVault();

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

    /// @dev Does not log anything because the ids (logged in the parent vault) are enough.
    function allocateIn(bytes memory data, uint256 assets) external returns (bytes32[] memory) {
        require(data.length == 0, InvalidData());
        require(msg.sender == parentVault, NotAuthorized());

        uint256 loss =
            assetsInVault.zeroFloorSub(IERC4626(vault).previewRedeem(IERC4626(vault).balanceOf(address(this))));
        if (loss > 0) realisableLoss += loss;

        IERC4626(vault).deposit(assets, address(this));
        assetsInVault = IERC4626(vault).previewRedeem(IERC4626(vault).balanceOf(address(this)));

        bytes32[] memory ids = new bytes32[](1);
        ids[0] = keccak256(abi.encode("vault", vault));
        return ids;
    }

    /// @dev Does not log anything because the ids (logged in the parent vault) are enough.
    function allocateOut(bytes memory data, uint256 assets) external returns (bytes32[] memory) {
        require(data.length == 0, InvalidData());
        require(msg.sender == parentVault, NotAuthorized());

        uint256 loss =
            assetsInVault.zeroFloorSub(IERC4626(vault).previewRedeem(IERC4626(vault).balanceOf(address(this))));
        if (loss > 0) realisableLoss += loss;

        IERC4626(vault).withdraw(assets, address(this), address(this));
        assetsInVault = IERC4626(vault).previewRedeem(IERC4626(vault).balanceOf(address(this)));

        bytes32[] memory ids = new bytes32[](1);
        ids[0] = keccak256(abi.encode("vault", vault));
        return ids;
    }

    function realiseLoss(bytes memory) external returns (uint256, bytes32[] memory) {
        require(msg.sender == parentVault, NotAuthorized());
        uint256 res = realisableLoss;
        realisableLoss = 0;

        bytes32[] memory ids = new bytes32[](1);
        ids[0] = keccak256(abi.encode("vault", vault));
        return (res, ids);
    }

    function skim(address token) external {
        require(msg.sender == skimRecipient, NotAuthorized());
        require(token != vault, CantSkimVault());
        uint256 balance = IERC20(token).balanceOf(address(this));
        SafeERC20Lib.safeTransfer(token, skimRecipient, balance);
        emit Skim(token, balance);
    }
}
