// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Morpho Association
pragma solidity 0.8.28;

import {IMorpho, MarketParams, Id} from "../../lib/morpho-blue/src/interfaces/IMorpho.sol";
import {MarketParamsLib} from "../../lib/morpho-blue/src/libraries/MarketParamsLib.sol";
import {SharesMathLib} from "../../lib/morpho-blue/src/libraries/SharesMathLib.sol";
import {IVaultV2} from "../interfaces/IVaultV2.sol";
import {IERC20} from "../interfaces/IERC20.sol";
import {IMorphoMarketV1Adapter, MarketPosition} from "./interfaces/IMorphoMarketV1Adapter.sol";
import {SafeERC20Lib} from "../libraries/SafeERC20Lib.sol";
import {
    AdaptiveCurveIrmLib
} from "../../lib/morpho-blue-irm/src/adaptive-curve-irm/libraries/periphery/AdaptiveCurveIrmLib.sol";

/// @dev Morpho Market V1 is also known as Morpho Blue.
/// @dev This adapter must be used with Morpho Market V1 that are protected against inflation attacks with an initial
/// supply. Following resource is relevant: https://docs.openzeppelin.com/contracts/5.x/erc4626#inflation-attack.
/// @dev Rounding error losses on supply/withdraw are realizable.
/// @dev If expectedSupplyAssets reverts for a market of the marketIds, realAssets will revert and the vault will not be
/// able to accrueInterest.
/// @dev Upon interest accrual, the vault calls realAssets(). If there are too many markets, it could cause issues such
/// as expensive interactions, even DOS, because of the gas.
/// @dev Shouldn't be used alongside another adapter that re-uses the last id (abi.encode("this/marketParams",
/// address(this), marketParams)).
/// @dev Markets get removed from the marketIds when the allocation is zero, but it doesn't mean that the adapter has
/// zero shares on the market.
/// @dev This adapter can only be used for markets with the adaptive curve irm.
contract MorphoMarketV1Adapter is IMorphoMarketV1Adapter {
    using MarketParamsLib for MarketParams;
    using SharesMathLib for uint128;

    /* IMMUTABLES */

    address public immutable factory;
    address public immutable parentVault;
    address public immutable asset;
    address public immutable morpho;
    bytes32 public immutable adapterId;
    address public immutable adaptiveCurveIrm;

    /* STORAGE */

    address public skimRecipient;
    bytes32[] public marketIds;
    mapping(bytes32 marketId => MarketPosition) public positions;
    mapping(bytes32 marketId => uint256) public burnSharesExecutableAt;

    function marketIdsLength() external view returns (uint256) {
        return marketIds.length;
    }

    /* FUNCTIONS */

    constructor(address _parentVault, address _morpho, address _adaptiveCurveIrm) {
        factory = msg.sender;
        parentVault = _parentVault;
        morpho = _morpho;
        asset = IVaultV2(_parentVault).asset();
        adapterId = keccak256(abi.encode("this", address(this)));
        adaptiveCurveIrm = _adaptiveCurveIrm;
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

    function submitBurnShares(bytes32 marketId) external {
        require(msg.sender == IVaultV2(parentVault).curator(), NotAuthorized());
        require(burnSharesExecutableAt[marketId] == 0, AlreadyPending());
        burnSharesExecutableAt[marketId] =
            block.timestamp + IVaultV2(parentVault).timelock(IVaultV2.removeAdapter.selector);
        emit SubmitBurnShares(marketId, burnSharesExecutableAt[marketId]);
    }

    function revokeBurnShares(bytes32 marketId) external {
        require(
            msg.sender == IVaultV2(parentVault).curator() || IVaultV2(parentVault).isSentinel(msg.sender),
            NotAuthorized()
        );
        require(burnSharesExecutableAt[marketId] != 0, NotPending());
        burnSharesExecutableAt[marketId] = 0;
        emit RevokeBurnShares(marketId);
    }

    /// @dev Deallocate 0 from the vault after burning shares to update the allocation there.
    function burnShares(bytes32 marketId) external {
        require(burnSharesExecutableAt[marketId] != 0, NotTimelocked());
        require(block.timestamp >= burnSharesExecutableAt[marketId], TimelockNotExpired());
        burnSharesExecutableAt[marketId] = 0;
        uint256 supplySharesBefore = positions[marketId].supplyShares;
        positions[marketId].supplyShares = 0;
        emit BurnShares(marketId, supplySharesBefore);
    }

    /// @dev Does not log anything because the ids (logged in the parent vault) are enough.
    /// @dev Returns the ids of the allocation and the change in allocation.
    function allocate(bytes memory data, uint256 assets, bytes4, address) external returns (bytes32[] memory, int256) {
        MarketParams memory marketParams = abi.decode(data, (MarketParams));
        require(msg.sender == parentVault, NotAuthorized());
        require(marketParams.loanToken == asset, LoanAssetMismatch());
        require(marketParams.irm == adaptiveCurveIrm, IrmMismatch());
        bytes32 marketId = Id.unwrap(marketParams.id());
        MarketPosition storage position = positions[marketId];

        uint256 mintedShares;
        if (assets > 0) {
            (, mintedShares) = IMorpho(morpho).supply(marketParams, assets, 0, address(this), hex"");
            require(mintedShares >= assets, SharePriceAboveOne());
            position.supplyShares += uint128(mintedShares);
        }

        uint256 oldAllocation = position.allocation;
        uint256 newAllocation = realAssets(marketId);
        updateList(marketId, oldAllocation, newAllocation);
        position.allocation = uint128(newAllocation);
        // Safe casts because Market V1 bounds the total supply of the underlying token, and allocation is less than the
        // max total assets of the vault.
        int256 change = int256(newAllocation) - int256(oldAllocation);

        emit Allocate(marketId, change, mintedShares);

        return (ids(marketParams), change);
    }

    /// @dev Does not log anything because the ids (logged in the parent vault) are enough.
    /// @dev Returns the ids of the deallocation and the change in allocation.
    function deallocate(bytes memory data, uint256 assets, bytes4, address)
        external
        returns (bytes32[] memory, int256)
    {
        MarketParams memory marketParams = abi.decode(data, (MarketParams));
        require(msg.sender == parentVault, NotAuthorized());
        require(marketParams.loanToken == asset, LoanAssetMismatch());
        require(marketParams.irm == adaptiveCurveIrm, IrmMismatch());
        bytes32 marketId = Id.unwrap(marketParams.id());
        MarketPosition storage position = positions[marketId];

        uint256 burnedShares;
        if (assets > 0) {
            (, burnedShares) = IMorpho(morpho).withdraw(marketParams, assets, 0, address(this), address(this));
            position.supplyShares -= uint128(burnedShares);
        }

        uint256 oldAllocation = position.allocation;
        uint256 newAllocation = realAssets(marketId);
        updateList(marketId, oldAllocation, newAllocation);
        position.allocation = uint128(newAllocation);
        // Safe casts because Market V1 bounds the total supply of the underlying token, and allocation is less than the
        // max total assets of the vault.
        int256 change = int256(newAllocation) - int256(oldAllocation);

        emit Deallocate(marketId, change, burnedShares);

        return (ids(marketParams), change);
    }

    function updateList(bytes32 marketId, uint256 oldAllocation, uint256 newAllocation) internal {
        if (oldAllocation > 0 && newAllocation == 0) {
            for (uint256 i = 0; i < marketIds.length; i++) {
                if (marketIds[i] == marketId) {
                    marketIds[i] = marketIds[marketIds.length - 1];
                    marketIds.pop();
                    break;
                }
            }
        } else if (oldAllocation == 0 && newAllocation > 0) {
            marketIds.push(marketId);
        }
    }

    function realAssets(bytes32 marketId) public view returns (uint256) {
        (uint256 totalSupplyAssets, uint256 totalSupplyShares,,) =
            AdaptiveCurveIrmLib.expectedMarketBalances(morpho, marketId, adaptiveCurveIrm);

        return positions[marketId].supplyShares.toAssetsDown(totalSupplyAssets, totalSupplyShares);
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
        for (uint256 i = 0; i < marketIds.length; i++) {
            _realAssets += realAssets(marketIds[i]);
        }
        return _realAssets;
    }
}
