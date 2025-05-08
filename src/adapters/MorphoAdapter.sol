// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.28;

import {IMorpho, MarketParams} from "../../lib/morpho-blue/src/interfaces/IMorpho.sol";
import {IVaultV2} from "../interfaces/IVaultV2.sol";
import {IERC20} from "../interfaces/IERC20.sol";
import {IAdapter} from "../interfaces/IAdapter.sol";
import {SafeERC20Lib} from "../libraries/SafeERC20Lib.sol";

contract MorphoAdapter is IAdapter {
    /* IMMUTABLES */

    address public immutable parentVault;
    address public immutable morpho;

    /* STORAGE */

    address public skimRecipient;

    /* EVENTS */

    event SetSkimRecipient(address indexed newSkimRecipient);
    event Skim(address indexed token, uint256 assets);

    /* ERRORS */

    error NotAuthorized();

    /* FUNCTIONS */

    constructor(address _parentVault, address _morpho) {
        morpho = _morpho;
        parentVault = _parentVault;
        SafeERC20Lib.safeApprove(IVaultV2(_parentVault).asset(), _morpho, type(uint256).max);
        SafeERC20Lib.safeApprove(IVaultV2(_parentVault).asset(), _parentVault, type(uint256).max);
    }

    function setSkimRecipient(address newSkimRecipient) external {
        require(msg.sender == IVaultV2(parentVault).owner(), NotAuthorized());
        skimRecipient = newSkimRecipient;
        emit SetSkimRecipient(newSkimRecipient);
    }

    function skim(address token) external {
        require(msg.sender == skimRecipient, NotAuthorized());
        uint256 balance = IERC20(token).balanceOf(address(this));
        SafeERC20Lib.safeTransfer(token, skimRecipient, balance);
        emit Skim(token, balance);
    }

    /// @dev Does not log anything because the ids (logged in the parent vault) are enough.
    function allocate(bytes memory data, uint256 assets) external returns (bytes32[] memory) {
        require(msg.sender == parentVault, NotAuthorized());
        MarketParams memory marketParams = abi.decode(data, (MarketParams));
        IMorpho(morpho).supply(marketParams, assets, 0, address(this), hex"");
        return ids(marketParams);
    }

    /// @dev Does not log anything because the ids (logged in the parent vault) are enough.
    function deallocate(bytes memory data, uint256 assets) external returns (bytes32[] memory) {
        require(msg.sender == parentVault, NotAuthorized());
        MarketParams memory marketParams = abi.decode(data, (MarketParams));
        IMorpho(morpho).withdraw(marketParams, assets, 0, address(this), address(this));
        return ids(marketParams);
    }

    function ids(MarketParams memory marketParams) internal view returns (bytes32[] memory) {
        bytes32[] memory ids_ = new bytes32[](3);
        ids_[0] = keccak256(abi.encode("adapter", address(this)));
        ids_[1] = keccak256(abi.encode("collateralToken", marketParams.collateralToken));
        ids_[2] = keccak256(
            abi.encode(
                "collateralToken/oracle/lltv", marketParams.collateralToken, marketParams.oracle, marketParams.lltv
            )
        );
        return ids_;
    }
}
