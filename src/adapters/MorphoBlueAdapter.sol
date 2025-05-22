// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.28;

import {IMorpho, MarketParams, Id} from "../../lib/morpho-blue/src/interfaces/IMorpho.sol";
import {MorphoBalancesLib} from "../../lib/morpho-blue/src/libraries/periphery/MorphoBalancesLib.sol";
import {MarketParamsLib} from "../../lib/morpho-blue/src/libraries/MarketParamsLib.sol";
import {IVaultV2} from "../interfaces/IVaultV2.sol";
import {IERC20} from "../interfaces/IERC20.sol";
import {IMorphoBlueAdapter} from "./interfaces/IMorphoBlueAdapter.sol";
import {SafeERC20Lib} from "../libraries/SafeERC20Lib.sol";
import {MathLib} from "../libraries/MathLib.sol";

contract MorphoBlueAdapter is IMorphoBlueAdapter {
    using MathLib for uint256;
    using MorphoBalancesLib for IMorpho;
    using MarketParamsLib for MarketParams;

    /* IMMUTABLES */

    address public immutable parentVault;
    address public immutable morpho;

    /* STORAGE */

    address public skimRecipient;
    mapping(Id => uint256) public assetsInMarket;
    mapping(Id => uint256) public realizableLoss;

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

    /// @dev Skims the adapter's balance of `token` and sends it to `skimRecipient`.
    /// @dev This is useful to handle rewards that the adapter has earned.
    function skim(address token) external {
        require(msg.sender == skimRecipient, NotAuthorized());
        uint256 balance = IERC20(token).balanceOf(address(this));
        SafeERC20Lib.safeTransfer(token, skimRecipient, balance);
        emit Skim(token, balance);
    }

    /// @dev Does not log anything because the ids (logged in the parent vault) are enough.
    /// @dev Returns the ids of the allocation and the potential loss.
    function allocate(bytes memory data, uint256 assets) external returns (bytes32[] memory, uint256) {
        require(msg.sender == parentVault, NotAuthorized());
        MarketParams memory marketParams = abi.decode(data, (MarketParams));
        Id marketId = marketParams.id();

        // To accrue interest only one time.
        IMorpho(morpho).accrueInterest(marketParams);

        uint256 _assetsInMarket = assetsInMarket[marketId];
        uint256 newAssetsInMarket = IMorpho(morpho).expectedSupplyAssets(marketParams, address(this));
        realizableLoss[marketId] += _assetsInMarket.zeroFloorSub(newAssetsInMarket);
        uint256 interest = newAssetsInMarket.zeroFloorSub(_assetsInMarket);
        if (assets > 0) IMorpho(morpho).supply(marketParams, assets, 0, address(this), hex"");
        assetsInMarket[marketId] = IMorpho(morpho).expectedSupplyAssets(marketParams, address(this));

        return (ids(marketParams), interest);
    }

    /// @dev Does not log anything because the ids (logged in the parent vault) are enough.
    /// @dev Returns the ids of the deallocation and the potential loss.
    function deallocate(bytes memory data, uint256 assets) external returns (bytes32[] memory, uint256) {
        require(msg.sender == parentVault, NotAuthorized());
        MarketParams memory marketParams = abi.decode(data, (MarketParams));
        Id marketId = marketParams.id();

        // To accrue interest only one time.
        IMorpho(morpho).accrueInterest(marketParams);
        uint256 _assetsInMarket = assetsInMarket[marketId];
        uint256 newAssetsInMarket = IMorpho(morpho).expectedSupplyAssets(marketParams, address(this));
        realizableLoss[marketId] += _assetsInMarket.zeroFloorSub(newAssetsInMarket);
        uint256 interest = newAssetsInMarket.zeroFloorSub(_assetsInMarket);
        if (assets > 0) IMorpho(morpho).withdraw(marketParams, assets, 0, address(this), address(this));
        assetsInMarket[marketId] = IMorpho(morpho).expectedSupplyAssets(marketParams, address(this));

        return (ids(marketParams), interest);
    }

    function realizeLoss(bytes memory data) external returns (bytes32[] memory, uint256) {
        require(msg.sender == parentVault, NotAuthorized());
        MarketParams memory marketParams = abi.decode(data, (MarketParams));
        Id marketId = marketParams.id();

        uint256 newAssetsInMarket = IMorpho(morpho).expectedSupplyAssets(marketParams, address(this));
        uint256 loss = realizableLoss[marketId] + assetsInMarket[marketId].zeroFloorSub(newAssetsInMarket);
        realizableLoss[marketId] = 0;
        assetsInMarket[marketId] = newAssetsInMarket;

        return (ids(marketParams), loss);
    }

    /// @dev Returns adapter's ids.
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
