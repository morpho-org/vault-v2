// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.28;

import {IMorpho, MarketParams, Id} from "../../lib/morpho-blue/src/interfaces/IMorpho.sol";
import {MorphoBalancesLib} from "../../lib/morpho-blue/src/libraries/periphery/MorphoBalancesLib.sol";
import {MarketParamsLib} from "../../lib/morpho-blue/src/libraries/MarketParamsLib.sol";
import {IVaultV2} from "../interfaces/IVaultV2.sol";
import {IERC20} from "../interfaces/IERC20.sol";
import {IMorphoAdapter} from "./interfaces/IMorphoAdapter.sol";
import {SafeERC20Lib} from "../libraries/SafeERC20Lib.sol";
import {MathLib} from "../libraries/MathLib.sol";

contract MorphoAdapter is IMorphoAdapter {
    using MathLib for uint256;
    using MorphoBalancesLib for IMorpho;
    using MarketParamsLib for MarketParams;

    /* IMMUTABLES */

    address public immutable parentVault;
    address public immutable morpho;

    /* STORAGE */

    address public skimRecipient;
    mapping(Id => uint256) public assetsInMarketIfNoLoss;

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
        Id marketId = marketParams.id();

        if (assets > 0) IMorpho(morpho).supply(marketParams, assets, 0, address(this), hex"");
        uint256 assetsInMarket = IMorpho(morpho).expectedSupplyAssets(marketParams, address(this));
        assetsInMarketIfNoLoss[marketId] = max(assetsInMarketIfNoLoss[marketId] + assets, assetsInMarket);

        return ids(marketParams);
    }

    /// @dev Does not log anything because the ids (logged in the parent vault) are enough.
    function deallocate(bytes memory data, uint256 assets) external returns (bytes32[] memory) {
        require(msg.sender == parentVault, NotAuthorized());
        MarketParams memory marketParams = abi.decode(data, (MarketParams));
        Id marketId = marketParams.id();

        if (assets > 0) IMorpho(morpho).withdraw(marketParams, assets, 0, address(this), address(this));
        uint256 assetsInMarket = IMorpho(morpho).expectedSupplyAssets(marketParams, address(this));
        assetsInMarketIfNoLoss[marketId] = max(assetsInMarketIfNoLoss[marketId] - assets, assetsInMarket);

        return ids(marketParams);
    }

    function realizeLoss(bytes memory data) external returns (uint256, bytes32[] memory) {
        require(msg.sender == parentVault, NotAuthorized());
        MarketParams memory marketParams = abi.decode(data, (MarketParams));
        Id marketId = marketParams.id();
        uint256 assetsInMarket = IMorpho(morpho).expectedSupplyAssets(marketParams, address(this));
        uint256 loss = assetsInMarketIfNoLoss[marketId].zeroFloorSub(assetsInMarket);
        assetsInMarketIfNoLoss[marketId] = assetsInMarket;
        return (loss, ids(marketParams));
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

function max(uint256 a, uint256 b) pure returns (uint256) {
    return a > b ? a : b;
}
