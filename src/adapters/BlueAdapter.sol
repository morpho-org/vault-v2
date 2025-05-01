// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.28;

import {IMorpho, MarketParams} from "../../lib/morpho-blue/src/interfaces/IMorpho.sol";
import {IVaultV2} from "../interfaces/IVaultV2.sol";
import {SafeERC20Lib} from "../libraries/SafeERC20Lib.sol";
import {IERC20} from "../interfaces/IERC20.sol";

contract BlueAdapter {
    /* IMMUTABLES */

    address public immutable parentVault;
    address public immutable morpho;

    /* STORAGE */

    address public skimRecipient;

    /* FUNCTIONS */

    constructor(address _parentVault, address _morpho) {
        morpho = _morpho;
        parentVault = _parentVault;
        SafeERC20Lib.safeApprove(IVaultV2(_parentVault).asset(), _morpho, type(uint256).max);
        SafeERC20Lib.safeApprove(IVaultV2(_parentVault).asset(), _parentVault, type(uint256).max);
    }

    function ids(MarketParams memory marketParams) public pure returns (bytes32[] memory) {
        bytes32[] memory ids = new bytes32[](1);
        ids[0] = keccak256(
            abi.encode(
                "collateralToken/oracle/lltv", marketParams.collateralToken, marketParams.oracle, marketParams.lltv
            )
        );
        return ids;
    }

    function setSkimRecipient(address newSkimRecipient) external {
        require(msg.sender == IVaultV2(parentVault).owner(), "not authorized");
        skimRecipient = newSkimRecipient;
    }

    function allocateIn(bytes memory data, uint256 assets) external returns (bytes32[] memory) {
        require(msg.sender == parentVault, "not authorized");
        MarketParams memory marketParams = abi.decode(data, (MarketParams));
        IMorpho(morpho).supply(marketParams, assets, 0, address(this), hex"");
        return ids(marketParams);
    }

    function allocateOut(bytes memory data, uint256 assets) external returns (bytes32[] memory) {
        require(msg.sender == parentVault, "not authorized");
        MarketParams memory marketParams = abi.decode(data, (MarketParams));
        IMorpho(morpho).withdraw(marketParams, assets, 0, address(this), address(this));
        return ids(marketParams);
    }

    function skim(address token) external {
        require(token != IVaultV2(parentVault).asset(), "can't skim underlying");
        SafeERC20Lib.safeTransfer(token, skimRecipient, IERC20(token).balanceOf(address(this)));
    }
}

contract BlueAdapterFactory {
    /* IMMUTABLES */

    address immutable morpho;

    /* STORAGE */

    // vault => adapter
    mapping(address => address) public adapter;

    /* EVENTS */

    event CreateBlueAdapter(address indexed vault, address indexed blueAdapter);

    /* FUNCTIONS */

    constructor(address _morpho) {
        morpho = _morpho;
    }

    function createBlueAdapter(address vault) external returns (address) {
        address blueAdapter = address(new BlueAdapter{salt: bytes32(0)}(vault, morpho));
        adapter[vault] = blueAdapter;
        emit CreateBlueAdapter(vault, blueAdapter);
        return blueAdapter;
    }
}
