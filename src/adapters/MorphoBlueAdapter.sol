// SPDX-License-Identifier: GPL-2.0-or-later
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
/// @dev `assets` are the recorded share value at the last allocate or deallocate.
struct PositionInMarket {
    uint128 shares;
    uint128 assets;
}

contract MorphoBlueAdapter is IMorphoBlueAdapter {
    using MathLib for uint256;
    using SharesMathLib for uint256;
    using MorphoBalancesLib for IMorpho;
    using MarketParamsLib for MarketParams;

    /* ERRORS */

    error MissingAssets();

    /* IMMUTABLES */

    address public immutable parentVault;
    address public immutable asset;
    address public immutable morpho;
    address public immutable irm;
    bytes32 public immutable adapterId;

    /* STORAGE */

    address public skimRecipient;
    mapping(Id => PositionInMarket) internal positionInMarket;

    /* FUNCTIONS */

    constructor(address _parentVault, address _morpho, address _irm) {
        parentVault = _parentVault;
        morpho = _morpho;
        irm = _irm;
        address _asset = IVaultV2(_parentVault).asset();
        asset = _asset;
        adapterId = keccak256(abi.encode("adapter", address(this)));
        SafeERC20Lib.safeApprove(_asset, _morpho, type(uint256).max);
        SafeERC20Lib.safeApprove(_asset, _parentVault, type(uint256).max);
    }

    function assetsInMarket(Id marketId) external view returns (uint256) {
        return positionInMarket[marketId].assets;
    }

    function sharesInMarket(Id marketId) external view returns (uint256) {
        return positionInMarket[marketId].shares;
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
    /// @dev Returns the ids of the allocation and the change in assets in the position.
    function allocate(bytes memory data, uint256 assets) external returns (bytes32[] memory, int256) {
        MarketParams memory marketParams = abi.decode(data, (MarketParams));
        require(msg.sender == parentVault, NotAuthorized());
        require(marketParams.loanToken == asset, LoanAssetMismatch());
        require(marketParams.irm == irm, IrmMismatch());

        PositionInMarket storage position = positionInMarket[marketParams.id()];
        if (assets > 0) {
            (, uint256 mintedShares) = IMorpho(morpho).supply(marketParams, assets, 0, address(this), hex"");
            position.shares += uint128(mintedShares);
        }
        uint256 newAssetsInMarket = expectedSupplyAssets(marketParams, position.shares);
        int256 change = int256(newAssetsInMarket) - int128(position.assets);
        position.assets = uint128(newAssetsInMarket);

        return (ids(marketParams), change);
    }

    /// @dev Does not log anything because the ids (logged in the parent vault) are enough.
    /// @dev Returns the ids of the deallocation and the change in assets in the position.
    /// @dev Always withdraw the full value of redeemed shares.
    /// @dev Assets withdrawn in excess of the requested amount are donated to the vault.
    function deallocate(bytes memory data, uint256 assets) external returns (bytes32[] memory, int256) {
        MarketParams memory marketParams = abi.decode(data, (MarketParams));
        require(msg.sender == parentVault, NotAuthorized());
        require(marketParams.loanToken == asset, LoanAssetMismatch());
        require(marketParams.irm == irm, IrmMismatch());

        PositionInMarket storage position = positionInMarket[marketParams.id()];
        uint withdrawnAssets;
        if (assets > 0) {
            (uint totalSupplyAssets, uint totalSupplyShares,,) = MorphoBalancesLib.expectedMarketBalances(IMorpho(morpho), marketParams);
            uint redeemedShares = assets.toSharesUp(totalSupplyAssets, totalSupplyShares);
            position.shares -= uint128(redeemedShares);
            (withdrawnAssets, ) = IMorpho(morpho).withdraw(marketParams, 0, redeemedShares, address(this), address(this));
        }
        require(withdrawnAssets >= assets, MissingAssets());

        IERC20(asset).transfer(parentVault,withdrawnAssets);
        uint256 newAssetsInMarket = expectedSupplyAssets(marketParams, position.shares);
        int256 change = int256(newAssetsInMarket) - int128(position.assets);
        position.assets = uint128(newAssetsInMarket);

        return (ids(marketParams), change);
    }

    /// @dev Returns adapter's ids.
    function ids(MarketParams memory marketParams) public view returns (bytes32[] memory) {
        bytes32[] memory ids_ = new bytes32[](3);
        ids_[0] = adapterId;
        ids_[1] = keccak256(abi.encode("collateralToken", marketParams.collateralToken));
        ids_[2] = keccak256(
            abi.encode(
                "collateralToken/oracle/lltv", marketParams.collateralToken, marketParams.oracle, marketParams.lltv
            )
        );
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
