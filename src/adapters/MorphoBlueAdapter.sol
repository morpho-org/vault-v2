// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Morpho Association
pragma solidity 0.8.28;

import {IMorpho, MarketParams, Id} from "../../lib/morpho-blue/src/interfaces/IMorpho.sol";
import {MorphoBalancesLib} from "../../lib/morpho-blue/src/libraries/periphery/MorphoBalancesLib.sol";
import {SharesMathLib} from "../../lib/morpho-blue/src/libraries/SharesMathLib.sol";
import {MarketParamsLib} from "../../lib/morpho-blue/src/libraries/MarketParamsLib.sol";
import {IVaultV2} from "../interfaces/IVaultV2.sol";
import {IERC20} from "../interfaces/IERC20.sol";
import {IMorphoBlueAdapter} from "./interfaces/IMorphoBlueAdapter.sol";
import {SafeERC20Lib} from "../libraries/SafeERC20Lib.sol";
import {MathLib} from "../libraries/MathLib.sol";

/// @dev `shares` are the recorded shares created by allocate and burned by deallocate.
/// @dev `allocation` are the share's value without taking into account unrealized losses.
struct Position {
    uint128 shares;
    uint128 allocation;
}

contract MorphoBlueAdapter is IMorphoBlueAdapter {
    using MathLib for uint256;
    using SharesMathLib for uint256;
    using MorphoBalancesLib for IMorpho;
    using MarketParamsLib for MarketParams;

    /* IMMUTABLES */

    address public immutable factory;
    address public immutable parentVault;
    address public immutable asset;
    address public immutable morpho;
    address public immutable irm;
    bytes32 public immutable adapterId;

    /* STORAGE */

    address public skimRecipient;
    mapping(Id => Position) internal position;

    /* FUNCTIONS */

    constructor(address _parentVault, address _morpho, address _irm) {
        factory = msg.sender;
        parentVault = _parentVault;
        morpho = _morpho;
        irm = _irm;
        asset = IVaultV2(_parentVault).asset();
        adapterId = keccak256(abi.encode("adapter", address(this)));
        SafeERC20Lib.safeApprove(asset, _morpho, type(uint256).max);
        SafeERC20Lib.safeApprove(asset, _parentVault, type(uint256).max);
    }

    function allocation(Id marketId) external view returns (uint256) {
        return position[marketId].allocation;
    }

    function shares(Id marketId) external view returns (uint256) {
        return position[marketId].shares;
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
        MarketParams memory marketParams = abi.decode(data, (MarketParams));
        Position storage _position = position[marketParams.id()];
        require(msg.sender == parentVault, NotAuthorized());
        require(marketParams.loanToken == asset, LoanAssetMismatch());
        require(marketParams.irm == irm, IrmMismatch());

        // To accrue interest only one time.
        IMorpho(morpho).accrueInterest(marketParams);

        uint256 interest = expectedSupplyAssets(marketParams, _position.shares).zeroFloorSub(_position.allocation);

        if (assets > 0) {
            (, uint256 mintedShares) = IMorpho(morpho).supply(marketParams, assets, 0, address(this), hex"");
            _position.shares += uint128(mintedShares);
        }

        _position.allocation = uint128(_position.allocation + interest + assets);

        return (ids(marketParams), interest);
    }

    /// @dev Does not log anything because the ids (logged in the parent vault) are enough.
    /// @dev Returns the ids of the deallocation and the potential loss.
    function deallocate(bytes memory data, uint256 assets) external returns (bytes32[] memory, uint256) {
        MarketParams memory marketParams = abi.decode(data, (MarketParams));
        Position storage _position = position[marketParams.id()];
        require(msg.sender == parentVault, NotAuthorized());
        require(marketParams.loanToken == asset, LoanAssetMismatch());
        require(marketParams.irm == irm, IrmMismatch());

        // To accrue interest only one time.
        IMorpho(morpho).accrueInterest(marketParams);

        uint256 interest = expectedSupplyAssets(marketParams, _position.shares).zeroFloorSub(_position.allocation);

        if (assets > 0) {
            (, uint256 redeemedShares) = IMorpho(morpho).withdraw(marketParams, assets, 0, address(this), address(this));
            _position.shares -= uint128(redeemedShares);
        }

        _position.allocation = uint128(_position.allocation + interest - assets);

        return (ids(marketParams), interest);
    }

    function realizeLoss(bytes memory data) external returns (bytes32[] memory, uint256) {
        MarketParams memory marketParams = abi.decode(data, (MarketParams));
        Position storage _position = position[marketParams.id()];
        require(msg.sender == parentVault, NotAuthorized());

        uint256 assetsInMarket = expectedSupplyAssets(marketParams, _position.shares);
        uint256 loss = _position.allocation - assetsInMarket;
        _position.allocation = uint128(assetsInMarket);

        return (ids(marketParams), loss);
    }

    /// @dev Returns adapter's ids.
    function ids(MarketParams memory marketParams) public view returns (bytes32[] memory) {
        bytes32[] memory ids_ = new bytes32[](4);
        ids_[0] = adapterId;
        ids_[1] = keccak256(abi.encode("collateralToken", marketParams.collateralToken));
        ids_[2] = keccak256(
            abi.encode(
                "collateralToken/oracle/lltv", marketParams.collateralToken, marketParams.oracle, marketParams.lltv
            )
        );
        ids_[3] = keccak256(abi.encode(address(this), marketParams));
        return ids_;
    }

    function expectedSupplyAssets(MarketParams memory marketParams, uint256 supplyShares)
        internal
        view
        returns (uint256)
    {
        (uint256 totalSupplyAssets, uint256 totalSupplyShares,,) =
            MorphoBalancesLib.expectedMarketBalances(IMorpho(morpho), marketParams);

        return supplyShares.toAssetsDown(totalSupplyAssets, totalSupplyShares);
    }
}
