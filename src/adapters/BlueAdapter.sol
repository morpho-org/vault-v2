// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.28;

import {IMorpho, MarketParams} from "../../lib/morpho-blue/src/interfaces/IMorpho.sol";
import {IERC20} from "../../lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {IVaultV2} from "../interfaces/IVaultV2.sol";
import {SafeTransferLib} from "../libraries/SafeTransferLib.sol";

contract BlueAdapter {
    IMorpho public immutable MORPHO;
    address public immutable VAULT;

    constructor(address _morpho, address _vault) {
        MORPHO = IMorpho(_morpho);
        VAULT = _vault;
        SafeTransferLib.safeApprove(IVaultV2(_vault).asset(), _morpho, type(uint256).max);
        SafeTransferLib.safeApprove(IVaultV2(_vault).asset(), _vault, type(uint256).max);
    }

    function allocateIn(bytes memory data, uint256 amount) external returns (bytes32[] memory ids) {
        require(msg.sender == VAULT, "not authorized");
        (address loanToken, address collateralToken, address oracle, address irm, uint256 lltv) =
            abi.decode(data, (address, address, address, address, uint256));

        MarketParams memory marketParams =
            MarketParams({loanToken: loanToken, collateralToken: collateralToken, oracle: oracle, irm: irm, lltv: lltv});

        ids = new bytes32[](2);
        ids[0] = keccak256(abi.encode("collateral", collateralToken, oracle, lltv));
        ids[1] = keccak256(abi.encode("irm", irm));

        MORPHO.supply(marketParams, amount, 0, address(this), hex"");
    }

    function allocateOut(bytes memory data, uint256 amount) external returns (bytes32[] memory ids) {
        require(msg.sender == VAULT, "not authorized");
        (address loanToken, address collateralToken, address oracle, address irm, uint256 lltv) =
            abi.decode(data, (address, address, address, address, uint256));

        MarketParams memory marketParams =
            MarketParams({loanToken: loanToken, collateralToken: collateralToken, oracle: oracle, irm: irm, lltv: lltv});

        ids = new bytes32[](2);
        ids[0] = keccak256(abi.encode("collateral", collateralToken, oracle, lltv));
        ids[1] = keccak256(abi.encode("irm", irm));

        MORPHO.withdraw(marketParams, amount, 0, address(this), address(this));
    }
}
