// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.28;

import {IMorpho, MarketParams, Id} from "../../lib/morpho-blue/src/interfaces/IMorpho.sol";
import {MorphoBalancesLib} from "../../lib/morpho-blue/src/libraries/periphery/MorphoBalancesLib.sol";
import {MarketParamsLib} from "../../lib/morpho-blue/src/libraries/MarketParamsLib.sol";
import {IVaultV2, IAdapter} from "../interfaces/IVaultV2.sol";
import {IERC20} from "../interfaces/IERC20.sol";
import {SafeERC20Lib} from "../libraries/SafeERC20Lib.sol";

contract MorphoAdapter is IAdapter {
    using MorphoBalancesLib for IMorpho;
    using MarketParamsLib for MarketParams;

    /* IMMUTABLES */

    address public immutable parentVault;
    address public immutable morpho;

    /* STORAGE */

    address public skimRecipient;
    mapping(Id => uint256) public lastAssetsInMarket;
    mapping(Id => uint256) public realisableLoss;

    /* EVENTS */

    event SetSkimRecipient(address indexed newSkimRecipient);
    event Skim(address indexed token, uint256 amount);

    /* ERRORS */

    error NotAuthorized();

    /* FUNCTIONS */

    constructor(address _parentVault, address _morpho) {
        morpho = _morpho;
        parentVault = _parentVault;
        SafeERC20Lib.safeApprove(IVaultV2(_parentVault).asset(), _morpho, type(uint256).max);
        SafeERC20Lib.safeApprove(IVaultV2(_parentVault).asset(), _parentVault, type(uint256).max);
    }

    function ids(MarketParams memory marketParams) internal pure returns (bytes32[] memory) {
        bytes32[] memory ids_ = new bytes32[](1);
        ids_[0] = keccak256(
            abi.encode(
                "collateralToken/oracle/lltv", marketParams.collateralToken, marketParams.oracle, marketParams.lltv
            )
        );
        return ids_;
    }

    function setSkimRecipient(address newSkimRecipient) external {
        require(msg.sender == IVaultV2(parentVault).owner(), NotAuthorized());
        skimRecipient = newSkimRecipient;
        emit SetSkimRecipient(newSkimRecipient);
    }

    /// @dev Does not log anything because the ids (logged in the parent vault) are enough.
    function allocateIn(bytes memory data, uint256 assets) external returns (bytes32[] memory) {
        require(msg.sender == parentVault, NotAuthorized());
        MarketParams memory marketParams = abi.decode(data, (MarketParams));

        if (assets > 0) IMorpho(morpho).supply(marketParams, assets, 0, address(this), hex"");

        IMorpho(morpho).accrueInterest(marketParams);
        uint256 assetsInMarket = IMorpho(morpho).expectedSupplyAssets(marketParams, address(this));
        Id marketId = marketParams.id();
        uint256 expectedAssets = lastAssetsInMarket[marketId] + assets;
        if (assetsInMarket < expectedAssets) {
            realisableLoss[marketId] += expectedAssets - assetsInMarket;
        }
        lastAssetsInMarket[marketId] = assetsInMarket;

        return ids(marketParams);
    }

    /// @dev Does not log anything because the ids (logged in the parent vault) are enough.
    function allocateOut(bytes memory data, uint256 assets) external returns (bytes32[] memory) {
        require(msg.sender == parentVault, NotAuthorized());
        MarketParams memory marketParams = abi.decode(data, (MarketParams));

        if (assets > 0) IMorpho(morpho).withdraw(marketParams, assets, 0, address(this), address(this));

        IMorpho(morpho).accrueInterest(marketParams);
        uint256 assetsInMarket = IMorpho(morpho).expectedSupplyAssets(marketParams, address(this));
        Id marketId = marketParams.id();
        uint256 expectedAssets = lastAssetsInMarket[marketId] - assets;
        if (assetsInMarket < expectedAssets) {
            realisableLoss[marketId] += expectedAssets - assetsInMarket;
        }
        lastAssetsInMarket[marketId] = assetsInMarket;

        return ids(marketParams);
    }

    function realiseLoss(bytes memory data) external returns (uint256, bytes32[] memory) {
        require(msg.sender == parentVault, NotAuthorized());
        MarketParams memory marketParams = abi.decode(data, (MarketParams));
        Id marketId = marketParams.id();
        uint256 res = realisableLoss[marketId];
        realisableLoss[marketId] = 0;
        return (res, ids(marketParams));
    }

    function skim(address token) external {
        require(msg.sender == skimRecipient, NotAuthorized());
        uint256 balance = IERC20(token).balanceOf(address(this));
        SafeERC20Lib.safeTransfer(token, skimRecipient, balance);
        emit Skim(token, balance);
    }
}
