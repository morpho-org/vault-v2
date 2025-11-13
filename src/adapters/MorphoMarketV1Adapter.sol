// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Morpho Association
pragma solidity 0.8.28;

import {IMorpho, MarketParams, Id} from "../../lib/morpho-blue/src/interfaces/IMorpho.sol";
import {MorphoBalancesLib} from "../../lib/morpho-blue/src/libraries/periphery/MorphoBalancesLib.sol";
import {MarketParamsLib} from "../../lib/morpho-blue/src/libraries/MarketParamsLib.sol";
import {SharesMathLib} from "../../lib/morpho-blue/src/libraries/SharesMathLib.sol";
import {IVaultV2} from "../interfaces/IVaultV2.sol";
import {IERC20} from "../interfaces/IERC20.sol";
import {IMorphoMarketV1Adapter} from "./interfaces/IMorphoMarketV1Adapter.sol";
import {SafeERC20Lib} from "../libraries/SafeERC20Lib.sol";

/// @dev Morpho Market V1 is also known as Morpho Blue.
/// @dev This adapter must be used with Morpho Market V1 that are protected against inflation attacks with an initial
/// supply. Following resource is relevant: https://docs.openzeppelin.com/contracts/5.x/erc4626#inflation-attack.
/// @dev Must not be used with a Morpho Market V1 with an Irm that can re-enter the parent vault or the adapter.
/// @dev Rounding error losses on supply/withdraw are realizable.
/// @dev If expectedSupplyAssets reverts, realAssets will revert and the vault will
/// not be able to accrueInterest.
/// @dev Shouldn't be used alongside another adapter that re-uses the adapter id (abi.encode("this",address(this))).
/// @dev The adapter returns 0 real assets when the allocation is zero, but it doesn't mean that the adapter has zero
/// shares on the market.
contract MorphoMarketV1Adapter is IMorphoMarketV1Adapter {
    using MarketParamsLib for MarketParams;
    using SharesMathLib for uint256;

    /* IMMUTABLES */

    address public immutable factory;
    address public immutable parentVault;
    address public immutable asset;
    address public immutable morpho;
    bytes32 public immutable adapterId;
    address public immutable collateralToken;
    address public immutable oracle;
    address public immutable irm;
    uint256 public immutable lltv;
    bytes32 public immutable collateralTokenId;

    /* STORAGE */

    address public skimRecipient;
    uint256 public supplyShares;

    /* FUNCTIONS */

    constructor(address _parentVault, address _morpho, MarketParams memory _marketParams) {
        factory = msg.sender;
        parentVault = _parentVault;
        morpho = _morpho;
        asset = IVaultV2(_parentVault).asset();
        collateralToken = _marketParams.collateralToken;
        oracle = _marketParams.oracle;
        irm = _marketParams.irm;
        lltv = _marketParams.lltv;

        adapterId = keccak256(abi.encode("this", address(this)));
        collateralTokenId = keccak256(abi.encode("collateralToken", collateralToken));
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
    function allocate(bytes memory, uint256 assets, bytes4, address) external returns (bytes32[] memory, int256) {
        require(msg.sender == parentVault, NotAuthorized());

        if (assets > 0) {
            (, uint256 mintedShares) = IMorpho(morpho).supply(marketParams(), assets, 0, address(this), hex"");
            supplyShares += mintedShares;
        }

        uint256 oldAllocation = IVaultV2(parentVault).allocation(adapterId);
        uint256 newAllocation = expectedSupplyAssets();

        // Safe casts because Market V1 bounds the total supply of the underlying token, and allocation is less than the
        // max total assets of the vault.
        return (ids(), int256(newAllocation) - int256(oldAllocation));
    }

    /// @dev Does not log anything because the ids (logged in the parent vault) are enough.
    /// @dev Returns the ids of the deallocation and the change in allocation.
    function deallocate(bytes memory, uint256 assets, bytes4, address) external returns (bytes32[] memory, int256) {
        require(msg.sender == parentVault, NotAuthorized());

        if (assets > 0) {
            (, uint256 redeemedShares) =
                IMorpho(morpho).withdraw(marketParams(), assets, 0, address(this), address(this));
            supplyShares -= redeemedShares;
        }

        uint256 oldAllocation = allocation();
        uint256 newAllocation = expectedSupplyAssets();

        // Safe casts because Market V1 bounds the total supply of the underlying token, and allocation is less than the
        // max total assets of the vault.
        return (ids(), int256(newAllocation) - int256(oldAllocation));
    }

    function allocation() public view returns (uint256) {
        return IVaultV2(parentVault).allocation(adapterId);
    }

    /// @dev Returns adapter's ids.
    function ids() public view returns (bytes32[] memory) {
        bytes32[] memory ids_ = new bytes32[](2);
        ids_[0] = adapterId;
        ids_[1] = collateralTokenId;
        return ids_;
    }

    function realAssets() external view returns (uint256) {
        return allocation() != 0 ? expectedSupplyAssets() : 0;
    }

    function marketParams() public view returns (MarketParams memory) {
        return MarketParams({loanToken: asset, collateralToken: collateralToken, oracle: oracle, irm: irm, lltv: lltv});
    }

    /* INTERNAL FUNCTIONS */

    function expectedSupplyAssets() internal view returns (uint256) {
        (uint256 totalSupplyAssets, uint256 totalSupplyShares,,) =
            MorphoBalancesLib.expectedMarketBalances(IMorpho(morpho), marketParams());

        return supplyShares.toAssetsDown(totalSupplyAssets, totalSupplyShares);
    }
}
