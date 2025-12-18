// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Morpho Association
pragma solidity 0.8.28;

import {IMorpho, MarketParams, Id} from "../../lib/morpho-blue/src/interfaces/IMorpho.sol";
import {MarketParamsLib} from "../../lib/morpho-blue/src/libraries/MarketParamsLib.sol";
import {SharesMathLib} from "../../lib/morpho-blue/src/libraries/SharesMathLib.sol";
import {IVaultV2} from "../interfaces/IVaultV2.sol";
import {IERC20} from "../interfaces/IERC20.sol";
import {IMorphoMarketV1AdapterV2} from "./interfaces/IMorphoMarketV1AdapterV2.sol";
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
/// @dev Before adding the adapter to the vault, its timelocks must be properly set.
/// @dev Donated shares are lost forever.
///
/// TIMELOCKS
/// @dev The system is the same as the one used in VaultV2. Dev comments in VaultV2.sol on timelocks also apply here.
///
/// BURN SHARES
/// @dev When submitting burnShares, it's recommended to put the caps of the market to zero to avoid losing more.
/// @dev Burning shares takes time, so reactive depositors might be able to exit before the share price reduction.
/// @dev It is possible to burn the shares of a market whose IRM reverts.
/// @dev Burnt shares are lost forever.
contract MorphoMarketV1AdapterV2 is IMorphoMarketV1AdapterV2 {
    using MarketParamsLib for MarketParams;
    using SharesMathLib for uint256;

    /* IMMUTABLES */

    address public immutable factory;
    address public immutable parentVault;
    address public immutable asset;
    address public immutable morpho;
    bytes32 public immutable adapterId;
    address public immutable adaptiveCurveIrm;

    /* TIMELOCKS STORAGE */

    mapping(bytes4 selector => uint256) public timelock;
    mapping(bytes4 selector => bool) public abdicated;
    mapping(bytes data => uint256) public executableAt;

    /* OTHER STORAGE */

    address public skimRecipient;
    bytes32[] public marketIds;
    mapping(bytes32 marketId => uint256) public supplyShares;

    /* GETTERS */

    function marketIdsLength() external view returns (uint256) {
        return marketIds.length;
    }

    /* CONSTRUCTOR */

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

    /* TIMELOCKS FUNCTIONS */

    /// @dev Will revert if the timelock value is type(uint256).max or any value that overflows when added to the block
    /// timestamp.
    function submit(bytes calldata data) external {
        require(msg.sender == IVaultV2(parentVault).curator(), Unauthorized());
        require(executableAt[data] == 0, DataAlreadyPending());

        // forge-lint: disable-next-item(unsafe-typecast) we explicitly want only the first bytes4.
        bytes4 selector = bytes4(data);
        // forge-lint: disable-next-item(unsafe-typecast) we explicitly want only the second bytes4.
        uint256 _timelock = selector == IMorphoMarketV1AdapterV2.decreaseTimelock.selector
            ? timelock[bytes4(data[4:8])]
            : timelock[selector];
        executableAt[data] = block.timestamp + _timelock;
        emit Submit(selector, data, executableAt[data]);
    }

    function timelocked() internal {
        bytes4 selector = bytes4(msg.data);
        require(executableAt[msg.data] != 0, DataNotTimelocked());
        require(block.timestamp >= executableAt[msg.data], TimelockNotExpired());
        require(!abdicated[selector], Abdicated());
        executableAt[msg.data] = 0;
        emit Accept(selector, msg.data);
    }

    function revoke(bytes calldata data) external {
        require(
            msg.sender == IVaultV2(parentVault).curator() || IVaultV2(parentVault).isSentinel(msg.sender),
            Unauthorized()
        );
        require(executableAt[data] != 0, DataNotTimelocked());
        executableAt[data] = 0;
        // forge-lint: disable-next-item(unsafe-typecast) we explicitly want only the first bytes4.
        bytes4 selector = bytes4(data);
        emit Revoke(msg.sender, selector, data);
    }

    /* CURATOR FUNCTIONS */

    /// @dev This function requires great caution because it can irreversibly disable submit for a selector.
    /// @dev Existing pending operations submitted before increasing a timelock can still be executed at the initial
    /// executableAt.
    function increaseTimelock(bytes4 selector, uint256 newDuration) external {
        timelocked();
        require(selector != IMorphoMarketV1AdapterV2.decreaseTimelock.selector, AutomaticallyTimelocked());
        require(newDuration >= timelock[selector], TimelockNotIncreasing());

        timelock[selector] = newDuration;
        emit IncreaseTimelock(selector, newDuration);
    }

    function decreaseTimelock(bytes4 selector, uint256 newDuration) external {
        timelocked();
        require(selector != IMorphoMarketV1AdapterV2.decreaseTimelock.selector, AutomaticallyTimelocked());
        require(newDuration <= timelock[selector], TimelockNotDecreasing());

        timelock[selector] = newDuration;
        emit DecreaseTimelock(selector, newDuration);
    }

    /// @dev This function requires great caution because it will irreversibly disable submit for a selector.
    /// @dev Existing pending operations submitted before abdicating can not be executed at the initial executableAt.
    function abdicate(bytes4 selector) external {
        timelocked();
        abdicated[selector] = true;
        emit Abdicate(selector);
    }

    function setSkimRecipient(address newSkimRecipient) external {
        timelocked();
        skimRecipient = newSkimRecipient;
        emit SetSkimRecipient(newSkimRecipient);
    }

    /// @dev Deallocate 0 from the vault after burning shares to update the allocation there.
    function burnShares(bytes32 marketId) external {
        timelocked();
        uint256 supplySharesBefore = supplyShares[marketId];
        supplyShares[marketId] = 0;
        emit BurnShares(marketId, supplySharesBefore);
    }

    /* OTHER FUNCTIONS */

    /// @dev Skims the adapter's balance of `token` and sends it to `skimRecipient`.
    /// @dev This is useful to handle rewards that the adapter has earned.
    function skim(address token) external {
        require(msg.sender == skimRecipient, Unauthorized());
        uint256 balance = IERC20(token).balanceOf(address(this));
        SafeERC20Lib.safeTransfer(token, skimRecipient, balance);
        emit Skim(token, balance);
    }

    /// @dev Returns the ids of the allocation and the change in allocation.
    function allocate(bytes memory data, uint256 assets, bytes4, address) external returns (bytes32[] memory, int256) {
        MarketParams memory marketParams = abi.decode(data, (MarketParams));
        require(msg.sender == parentVault, Unauthorized());
        require(marketParams.loanToken == asset, LoanAssetMismatch());
        require(marketParams.irm == adaptiveCurveIrm, IrmMismatch());
        bytes32 marketId = Id.unwrap(marketParams.id());

        uint256 mintedShares;
        if (assets > 0) {
            (, mintedShares) = IMorpho(morpho).supply(marketParams, assets, 0, address(this), hex"");
            require(mintedShares >= assets, SharePriceAboveOne());
            supplyShares[marketId] += mintedShares;
        }

        uint256 oldAllocation = allocation(marketParams);
        uint256 newAllocation = expectedSupplyAssets(marketId);
        updateList(marketId, oldAllocation, newAllocation);

        emit Allocate(marketId, newAllocation, mintedShares);

        // forge-lint: disable-next-item(unsafe-typecast) safe because Market V1 bounds the total supply of the
        // underlying token, and allocation is less than the max total assets of the vault.
        return (ids(marketParams), int256(newAllocation) - int256(oldAllocation));
    }

    /// @dev Returns the ids of the deallocation and the change in allocation.
    function deallocate(bytes memory data, uint256 assets, bytes4, address)
        external
        returns (bytes32[] memory, int256)
    {
        MarketParams memory marketParams = abi.decode(data, (MarketParams));
        require(msg.sender == parentVault, Unauthorized());
        require(marketParams.loanToken == asset, LoanAssetMismatch());
        require(marketParams.irm == adaptiveCurveIrm, IrmMismatch());
        bytes32 marketId = Id.unwrap(marketParams.id());

        uint256 burnedShares;
        if (assets > 0) {
            (, burnedShares) = IMorpho(morpho).withdraw(marketParams, assets, 0, address(this), address(this));
            supplyShares[marketId] -= burnedShares;
        }

        uint256 oldAllocation = allocation(marketParams);
        uint256 newAllocation = expectedSupplyAssets(marketId);
        updateList(marketId, oldAllocation, newAllocation);

        emit Deallocate(marketId, newAllocation, burnedShares);

        // forge-lint: disable-next-item(unsafe-typecast) safe because Market V1 bounds the total supply of the
        // underlying token, and allocation is less than the max total assets of the vault.
        return (ids(marketParams), int256(newAllocation) - int256(oldAllocation));
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

    /* VIEW FUNCTIONS */

    /// @dev Returns the expected supply assets of the market, taking into account the internal shares accounting.
    function expectedSupplyAssets(bytes32 marketId) public view returns (uint256) {
        uint256 _supplyShares = supplyShares[marketId];
        if (_supplyShares == 0) {
            return 0;
        } else {
            (uint256 totalSupplyAssets, uint256 totalSupplyShares,,) =
                AdaptiveCurveIrmLib.expectedMarketBalances(morpho, marketId, adaptiveCurveIrm);
            return _supplyShares.toAssetsDown(totalSupplyAssets, totalSupplyShares);
        }
    }

    /// @dev Returns the Vault's allocation for this market.
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
        for (uint256 i = 0; i < marketIds.length; i++) {
            _realAssets += expectedSupplyAssets(marketIds[i]);
        }
        return _realAssets;
    }
}
