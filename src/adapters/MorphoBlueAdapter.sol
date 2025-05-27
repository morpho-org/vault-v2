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

    address public immutable factory;
    address public immutable parentVault;
    address public immutable morpho;

    address public immutable loanToken;
    address public immutable collateralToken;
    address public immutable oracle;
    address public immutable irm;
    uint256 public immutable lltv;

    /// @dev An Id is a Morpho V1 market id.
    /// @dev This concept is separate from Vault V2 ids.
    Id public immutable marketId;

    bytes32 public immutable id0;
    bytes32 public immutable id1;
    bytes32 public immutable id2;

    /* STORAGE */

    address public skimRecipient;
    mapping(Id => uint256) public assetsInMarket;

    /* FUNCTIONS */

    constructor(address _parentVault, address _morpho, MarketParams memory _marketParams) {
        factory = msg.sender;
        morpho = _morpho;
        parentVault = _parentVault;

        loanToken = _marketParams.loanToken;
        collateralToken = _marketParams.collateralToken;
        oracle = _marketParams.oracle;
        irm = _marketParams.irm;
        lltv = _marketParams.lltv;
        marketId = _marketParams.id();

        id0 = keccak256(abi.encode("adapter", address(this)));
        id1 = keccak256(abi.encode("collateralToken", _marketParams.collateralToken));
        id2 = keccak256(
            abi.encode(
                "collateralToken/oracle/lltv", _marketParams.collateralToken, _marketParams.oracle, _marketParams.lltv
            )
        );

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
        require(data.length == 0, InvalidData());
        require(msg.sender == parentVault, NotAuthorized());

        MarketParams memory _marketParams = marketParams();

        // To accrue interest only one time.
        IMorpho(morpho).accrueInterest(_marketParams);
        uint256 loss =
            assetsInMarket[marketId].zeroFloorSub(IMorpho(morpho).expectedSupplyAssets(_marketParams, address(this)));
        if (assets > 0) IMorpho(morpho).supply(_marketParams, assets, 0, address(this), hex"");
        assetsInMarket[marketId] = IMorpho(morpho).expectedSupplyAssets(_marketParams, address(this));

        return (ids(), loss);
    }

    /// @dev Does not log anything because the ids (logged in the parent vault) are enough.
    /// @dev Returns the ids of the deallocation and the potential loss.
    function deallocate(bytes memory data, uint256 assets) external returns (bytes32[] memory, uint256) {
        require(data.length == 0, InvalidData());
        require(msg.sender == parentVault, NotAuthorized());

        MarketParams memory _marketParams = marketParams();

        // To accrue interest only one time.
        IMorpho(morpho).accrueInterest(_marketParams);
        uint256 loss =
            assetsInMarket[marketId].zeroFloorSub(IMorpho(morpho).expectedSupplyAssets(_marketParams, address(this)));
        if (assets > 0) IMorpho(morpho).withdraw(_marketParams, assets, 0, address(this), address(this));
        assetsInMarket[marketId] = IMorpho(morpho).expectedSupplyAssets(_marketParams, address(this));

        return (ids(), loss);
    }

    /// @dev Returns adapter's ids.
    function ids() internal view returns (bytes32[] memory) {
        bytes32[] memory ids_ = new bytes32[](3);
        ids_[0] = id0;
        ids_[1] = id1;
        ids_[2] = id2;
        return ids_;
    }

    /// @dev Return adapter's market params.
    function marketParams() public view returns (MarketParams memory) {
        return
            MarketParams({loanToken: loanToken, collateralToken: collateralToken, oracle: oracle, irm: irm, lltv: lltv});
    }
}
