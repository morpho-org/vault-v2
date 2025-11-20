// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Morpho Association
pragma solidity 0.8.28;

import {IMorpho, MarketParams, Id} from "../../lib/morpho-blue/src/interfaces/IMorpho.sol";
import {MorphoBalancesLib} from "../../lib/morpho-blue/src/libraries/periphery/MorphoBalancesLib.sol";
import {MarketParamsLib} from "../../lib/morpho-blue/src/libraries/MarketParamsLib.sol";
import {SharesMathLib} from "../../lib/morpho-blue/src/libraries/SharesMathLib.sol";
import {IVaultV2} from "../interfaces/IVaultV2.sol";
import {IERC20} from "../interfaces/IERC20.sol";
import {IMorphoMarketV1Adapter, MarketPosition} from "./interfaces/IMorphoMarketV1Adapter.sol";
import {SafeERC20Lib} from "../libraries/SafeERC20Lib.sol";
import {MarketParamsStore} from "./MarketParamsStore.sol";

/// @dev Morpho Market V1 is also known as Morpho Blue.
/// @dev This adapter must be used with Morpho Market V1 that are protected against inflation attacks with an initial
/// supply. Following resource is relevant: https://docs.openzeppelin.com/contracts/5.x/erc4626#inflation-attack.
/// @dev Must not be used with a Morpho Market V1 with an Irm that can re-enter the parent vault or the adapter.
/// @dev Rounding error losses on supply/withdraw are realizable.
/// @dev If expectedSupplyAssets reverts for a market of the marketParamsList, realAssets will revert and the vault will
/// not be able to accrueInterest.
/// @dev Upon interest accrual, the vault calls realAssets(). If there are too many markets, it could cause issues such
/// as expensive interactions, even DOS, because of the gas.
/// @dev Shouldn't be used alongside another adapter that re-uses the last id (abi.encode("this/marketParams",
/// address(this), marketParams)).
/// @dev Markets get removed from the marketParamsList when the allocation is zero, but it doesn't mean that the adapter
/// has zero shares on the market.
contract MorphoMarketV1Adapter is IMorphoMarketV1Adapter {
    using MarketParamsLib for MarketParams;
    using SharesMathLib for uint256;

    /* IMMUTABLES */

    address public immutable factory;
    address public immutable parentVault;
    address public immutable asset;
    address public immutable morpho;
    bytes32 public immutable adapterId;

    /* STORAGE */

    address public skimRecipient;
    address[] public marketParamsStoreList;
    mapping(Id marketId => MarketPosition) public positions;
    mapping(Id marketId => uint256) public burnSharesExecutableAt;

    function marketParamsListLength() external view returns (uint256) {
        return marketParamsStoreList.length;
    }

    function marketParamsList(uint256 index) external view returns (MarketParams memory) {
        (MarketParams memory marketParams,) = MarketParamsStore(marketParamsStoreList[index]).marketParamsAndId();
        return marketParams;
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

    function submitBurnShares(MarketParams memory marketParams) external {
        require(msg.sender == IVaultV2(parentVault).curator(), NotAuthorized());
        require(burnSharesExecutableAt[marketParams.id()] == 0, AlreadyPending());
        burnSharesExecutableAt[marketParams.id()] =
            block.timestamp + IVaultV2(parentVault).timelock(IVaultV2.removeAdapter.selector);
        emit SubmitBurnShares(marketParams, burnSharesExecutableAt[marketParams.id()]);
    }

    function revokeBurnShares(MarketParams memory marketParams) external {
        require(
            msg.sender == IVaultV2(parentVault).curator() || IVaultV2(parentVault).isSentinel(msg.sender),
            NotAuthorized()
        );
        require(burnSharesExecutableAt[marketParams.id()] != 0, NotPending());
        burnSharesExecutableAt[marketParams.id()] = 0;
        emit RevokeBurnShares(marketParams);
    }

    function burnShares(MarketParams memory marketParams) external {
        require(burnSharesExecutableAt[marketParams.id()] != 0, NotTimelocked());
        require(block.timestamp >= burnSharesExecutableAt[marketParams.id()], TimelockNotExpired());
        burnSharesExecutableAt[marketParams.id()] = 0;
        positions[marketParams.id()].supplyShares = 0;
        emit BurnShares(marketParams);
    }

    /// @dev Does not log anything because the ids (logged in the parent vault) are enough.
    /// @dev Returns the ids of the allocation and the change in allocation.
    function allocate(bytes memory data, uint256 assets, bytes4, address) external returns (bytes32[] memory, int256) {
        MarketParams memory marketParams = abi.decode(data, (MarketParams));
        require(msg.sender == parentVault, NotAuthorized());
        require(marketParams.loanToken == asset, LoanAssetMismatch());

        Id marketId = marketParams.id();
        MarketPosition storage position = positions[marketId];

        uint256 shares;
        if (assets > 0) {
            (, shares) = IMorpho(morpho).supply(marketParams, assets, 0, address(this), hex"");
            position.supplyShares += uint128(shares);
        }

        uint256 oldAllocation = position.allocation;
        uint256 _newAllocation = newAllocation(marketParams, position.supplyShares);
        updateList(marketParams, oldAllocation, _newAllocation);
        position.allocation = uint128(_newAllocation);

        emit Allocate(marketParams, _newAllocation, shares);

        // Safe casts because Market V1 bounds the total supply of the underlying token, and allocation is less than the
        // max total assets of the vault.
        return (ids(marketParams), int256(_newAllocation) - int256(oldAllocation));
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

        Id marketId = marketParams.id();
        MarketPosition storage position = positions[marketId];

        uint256 shares;
        if (assets > 0) {
            (, shares) = IMorpho(morpho).withdraw(marketParams, assets, 0, address(this), address(this));
            position.supplyShares -= uint128(shares);
        }

        uint256 oldAllocation = position.allocation;
        uint256 _newAllocation = newAllocation(marketParams, position.supplyShares);
        position.allocation = uint128(_newAllocation);
        updateList(marketParams, oldAllocation, _newAllocation);

        emit Deallocate(marketParams, _newAllocation, shares);

        // Safe casts because Market V1 bounds the total supply of the underlying token, and allocation is less than the
        // max total assets of the vault.
        return (ids(marketParams), int256(_newAllocation) - int256(oldAllocation));
    }

    function updateList(MarketParams memory marketParams, uint256 oldAllocation, uint256 _newAllocation) internal {
        if (oldAllocation > 0 && _newAllocation == 0) {
            Id marketId = marketParams.id();
            for (uint256 i = 0; i < marketParamsStoreList.length; i++) {
                (, bytes32 currentMarketId) = MarketParamsStore(marketParamsStoreList[i]).marketParamsAndId();
                if (currentMarketId == Id.unwrap(marketId)) {
                    marketParamsStoreList[i] = marketParamsStoreList[marketParamsStoreList.length - 1];
                    marketParamsStoreList.pop();
                    break;
                }
            }
        } else if (oldAllocation == 0 && _newAllocation > 0) {
            address marketParamsStore = address(new MarketParamsStore(marketParams));
            marketParamsStoreList.push(marketParamsStore);
            emit MarketParamsAdded(marketParamsStore);
        }
    }

    function newAllocation(MarketParams memory marketParams, uint256 shares) internal view returns (uint256) {
        (uint256 totalSupplyAssets, uint256 totalSupplyShares,,) =
            MorphoBalancesLib.expectedMarketBalances(IMorpho(morpho), marketParams);
        return shares.toAssetsDown(totalSupplyAssets, totalSupplyShares);
    }

    function expectedSupplyAssets(MarketParams memory marketParams) public view returns (uint256) {
        return newAllocation(marketParams, positions[marketParams.id()].supplyShares);
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
        for (uint256 i = 0; i < marketParamsStoreList.length; i++) {
            (MarketParams memory marketParams, bytes32 marketId) =
                MarketParamsStore(marketParamsStoreList[i]).marketParamsAndId();
            _realAssets += newAllocation(marketParams, positions[Id.wrap(marketId)].supplyShares);
        }
        return _realAssets;
    }
}
