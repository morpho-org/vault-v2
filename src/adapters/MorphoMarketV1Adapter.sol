// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Morpho Association
pragma solidity 0.8.28;

import {IMorpho, MarketParams, Id} from "../../lib/morpho-blue/src/interfaces/IMorpho.sol";
import {MorphoBalancesLib} from "../../lib/morpho-blue/src/libraries/periphery/MorphoBalancesLib.sol";
import {MorphoLib} from "../../lib/morpho-blue/src/libraries/periphery/MorphoLib.sol";
import {MarketParamsLib} from "../../lib/morpho-blue/src/libraries/MarketParamsLib.sol";
import {IVaultV2} from "../interfaces/IVaultV2.sol";
import {IERC20} from "../interfaces/IERC20.sol";
import {IMorphoMarketV1Adapter} from "./interfaces/IMorphoMarketV1Adapter.sol";
import {SafeERC20Lib} from "../libraries/SafeERC20Lib.sol";

/// @dev Morpho Market v1 is also known as Morpho Blue.
/// @dev This adapter must be used with Morpho Market v1 that are protected against inflation attacks with an initial
/// supply. Following resource is relevant: https://docs.openzeppelin.com/contracts/5.x/erc4626#inflation-attack.
/// @dev Must not be used with a Morpho Market v1 with an Irm that can re-enter the parent vault.
/// @dev Losses that correspond to rounding errors are realizable.
/// @dev If expectedSupplyAssets reverts for a market of the marketParamsList, realAssets will revert and the vault will
/// not be able to accrueInterest.
contract MorphoMarketV1Adapter is IMorphoMarketV1Adapter {
    using MarketParamsLib for MarketParams;
    using MorphoLib for IMorpho;

    /* IMMUTABLES */

    address public immutable factory;
    address public immutable parentVault;
    address public immutable asset;
    address public immutable morpho;
    bytes32 public immutable adapterId;

    /* STORAGE */

    address public skimRecipient;
    MarketParams[] public marketParamsList;

    function marketParamsListLength() external view returns (uint256) {
        return marketParamsList.length;
    }

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
    /// @dev Returns the ids of the allocation and the change in allocation.
    function allocate(bytes memory data, uint256 assets, bytes4, address) external returns (bytes32[] memory, int256) {
        MarketParams memory marketParams = abi.decode(data, (MarketParams));
        require(msg.sender == parentVault, NotAuthorized());
        require(marketParams.loanToken == asset, LoanAssetMismatch());

        uint256 sharesBefore = MorphoLib.supplyShares(IMorpho(morpho), marketParams.id(), address(this));
        uint256 suppliedShares;
        if (assets > 0) {
            (, suppliedShares) = IMorpho(morpho).supply(marketParams, assets, 0, address(this), hex"");
        }
        // Safe casts because Market v1 bounds the total supply of the underlying token, and allocation is less than the
        // max total assets of the vault.
        int256 change = int256(MorphoBalancesLib.expectedSupplyAssets(IMorpho(morpho), marketParams, address(this)))
            - int256(allocation(marketParams));

        if (sharesBefore == 0 && suppliedShares > 0) marketParamsList.push(marketParams);

        return (ids(marketParams), change);
    }

    /// @dev Does not log anything because the ids (logged in the parent vault) are enough.
    /// @dev Returns the ids of the deallocation and the change in allocation.
    function deallocate(bytes memory data, uint256 assets, bytes4, address)
        external
        returns (bytes32[] memory, int256)
    {
        MarketParams memory marketParams = abi.decode(data, (MarketParams));
        Id marketId = marketParams.id();
        require(msg.sender == parentVault, NotAuthorized());
        require(marketParams.loanToken == asset, LoanAssetMismatch());

        uint256 sharesBefore = MorphoLib.supplyShares(IMorpho(morpho), marketId, address(this));
        uint256 withdrawnShares;
        if (assets > 0) {
            (, withdrawnShares) = IMorpho(morpho).withdraw(marketParams, assets, 0, address(this), address(this));
        }
        // Safe casts because Market v1 bounds the total supply of the underlying token, and allocation is less than the
        // max total assets of the vault.
        int256 change = int256(MorphoBalancesLib.expectedSupplyAssets(IMorpho(morpho), marketParams, address(this)))
            - int256(allocation(marketParams));

        if (sharesBefore > 0 && withdrawnShares == sharesBefore) removeMarketFromList(marketId);

        return (ids(marketParams), change);
    }

    function removeDustMarketFromList(MarketParams memory marketParams) external {
        require(msg.sender == IVaultV2(parentVault).curator(), NotAuthorized());
        require(MorphoBalancesLib.expectedSupplyAssets(IMorpho(morpho), marketParams, address(this)) == 0);
        removeMarketFromList(marketParams.id());
    }

    function removeMarketFromList(Id marketId) internal {
        for (uint256 i = 0; i < marketParamsList.length; i++) {
            if (Id.unwrap(marketParamsList[i].id()) == Id.unwrap(marketId)) {
                marketParamsList[i] = marketParamsList[marketParamsList.length - 1];
                marketParamsList.pop();
                break;
            }
        }
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

    function realAssets() external view returns (uint256) {
        uint256 _realAssets = 0;
        for (uint256 i = 0; i < marketParamsList.length; i++) {
            _realAssets += MorphoBalancesLib.expectedSupplyAssets(IMorpho(morpho), marketParamsList[i], address(this));
        }
        return _realAssets;
    }
}
