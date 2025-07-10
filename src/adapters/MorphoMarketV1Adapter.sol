// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Morpho Association
pragma solidity 0.8.28;

import {IMorpho, MarketParams, Id} from "../../lib/morpho-blue/src/interfaces/IMorpho.sol";
import {MorphoBalancesLib} from "../../lib/morpho-blue/src/libraries/periphery/MorphoBalancesLib.sol";
import {SharesMathLib} from "../../lib/morpho-blue/src/libraries/SharesMathLib.sol";
import {MarketParamsLib} from "../../lib/morpho-blue/src/libraries/MarketParamsLib.sol";
import {IVaultV2} from "../interfaces/IVaultV2.sol";
import {IERC20} from "../interfaces/IERC20.sol";
import {IMorphoMarketV1Adapter} from "./interfaces/IMorphoMarketV1Adapter.sol";
import {SafeERC20Lib} from "../libraries/SafeERC20Lib.sol";
import {MathLib} from "../libraries/MathLib.sol";

/// @dev Morpho Market v1 is also known as Morpho Blue.
/// @dev This adapter must be used with Morpho Market v1 that are protected against inflation attacks with an initial
/// supply. Following resource is relevant: https://docs.openzeppelin.com/contracts/5.x/erc4626#inflation-attack.
contract MorphoMarketV1Adapter is IMorphoMarketV1Adapter {
    using MathLib for uint256;
    using SharesMathLib for uint256;
    using MorphoBalancesLib for IMorpho;
    using MarketParamsLib for MarketParams;

    /* IMMUTABLES */

    address public immutable factory;
    address public immutable parentVault;
    address public immutable asset;
    address public immutable morpho;
    bytes32 public immutable adapterId;

    /* STORAGE */

    address public skimRecipient;
    /// @dev `shares` are the recorded shares created by allocate and burned by deallocate.
    mapping(Id => uint256) public shares;

    /* FUNCTIONS */

    constructor(address _parentVault, address _morpho) {
        factory = msg.sender;
        parentVault = _parentVault;
        morpho = _morpho;
        asset = IVaultV2(_parentVault).asset();
        adapterId = keccak256(abi.encode("this", address(this)));
        SafeERC20Lib.safeApprove(asset, _morpho, type(uint256).max);
        SafeERC20Lib.safeApprove(asset, _parentVault, type(uint256).max);
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
    function allocate(bytes memory data, uint256 assets, bytes4, address)
        external
        returns (bytes32[] memory, uint256)
    {
        MarketParams memory marketParams = abi.decode(data, (MarketParams));
        Id marketId = marketParams.id();
        require(msg.sender == parentVault, NotAuthorized());
        require(marketParams.loanToken == asset, LoanAssetMismatch());

        uint256 interest = expectedSupplyAssets(marketParams, shares[marketId]).zeroFloorSub(allocation(marketParams));

        if (assets > 0) {
            (, uint256 mintedShares) = IMorpho(morpho).supply(marketParams, assets, 0, address(this), hex"");
            shares[marketId] += mintedShares;
        }

        return (ids(marketParams), interest);
    }

    /// @dev Does not log anything because the ids (logged in the parent vault) are enough.
    /// @dev Returns the ids of the deallocation and the potential loss.
    function deallocate(bytes memory data, uint256 assets, bytes4, address)
        external
        returns (bytes32[] memory, uint256)
    {
        MarketParams memory marketParams = abi.decode(data, (MarketParams));
        Id marketId = marketParams.id();
        require(msg.sender == parentVault, NotAuthorized());
        require(marketParams.loanToken == asset, LoanAssetMismatch());

        uint256 interest = expectedSupplyAssets(marketParams, shares[marketId]).zeroFloorSub(allocation(marketParams));

        if (assets > 0) {
            (, uint256 redeemedShares) = IMorpho(morpho).withdraw(marketParams, assets, 0, address(this), address(this));
            shares[marketId] -= redeemedShares;
        }

        return (ids(marketParams), interest);
    }

    function realizeLoss(bytes memory data, bytes4, address) external view returns (bytes32[] memory, uint256) {
        MarketParams memory marketParams = abi.decode(data, (MarketParams));
        require(marketParams.loanToken == asset, LoanAssetMismatch());

        uint256 loss = allocation(marketParams) - expectedSupplyAssets(marketParams, shares[marketParams.id()]);

        return (ids(marketParams), loss);
    }

    function allocation(MarketParams memory marketParams) public view returns (uint256) {
        return IVaultV2(parentVault).allocation(keccak256(abi.encode("this/marketParams", address(this), marketParams)));
    }

    /// @dev Returns adapter's ids.
    function ids(MarketParams memory marketParams) public view returns (bytes32[] memory) {
        bytes32[] memory ids_ = new bytes32[](3);
        ids_[0] = adapterId;
        ids_[1] = keccak256(abi.encode("collateralToken", marketParams.collateralToken));
        ids_[2] = keccak256(abi.encode("this/marketParams", address(this), marketParams));
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
