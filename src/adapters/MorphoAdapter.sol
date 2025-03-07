// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.28;

import {ERC4626, ERC20, IERC20} from "../../lib/openzeppelin-contracts/contracts/token/ERC20/extensions/ERC4626.sol";

import {IMorpho, MarketParams} from "../../lib/morpho-blue/src/interfaces/IMorpho.sol";
import {MorphoBalancesLib} from "../../lib/morpho-blue/src/libraries/periphery/MorphoBalancesLib.sol";

// To use to create a new market in VaultV2.
contract MorphoAdapter is ERC4626 {
    using MorphoBalancesLib for IMorpho;

    IMorpho public immutable MORPHO;

    // Market parameters
    address internal immutable LOAN_TOKEN;
    address internal immutable COLLATERAL_TOKEN;
    address internal immutable ORACLE;
    address internal immutable IRM;
    uint256 internal immutable LLTV;

    function marketParams() public view returns (MarketParams memory) {
        return MarketParams({
            loanToken: LOAN_TOKEN,
            collateralToken: COLLATERAL_TOKEN,
            oracle: ORACLE,
            irm: IRM,
            lltv: LLTV
        });
    }

    constructor(address _morpho, MarketParams memory _marketParams, string memory _name, string memory _symbol)
        ERC4626(IERC20(_marketParams.loanToken))
        ERC20(_name, _symbol)
    {
        MORPHO = IMorpho(_morpho);
        LOAN_TOKEN = _marketParams.loanToken;
        COLLATERAL_TOKEN = _marketParams.collateralToken;
        ORACLE = _marketParams.oracle;
        IRM = _marketParams.irm;
        LLTV = _marketParams.lltv;

        IERC20(_marketParams.loanToken).approve(_morpho, type(uint256).max);
    }

    function totalAssets() public view override returns (uint256) {
        return MORPHO.expectedSupplyAssets(marketParams(), address(this));
    }

    // TODO: we could use Morpho Blue shares instead of a new kind of shares.
    function _deposit(address caller, address receiver, uint256 assets, uint256 shares) internal override {
        super._deposit(caller, receiver, assets, shares);
        MORPHO.supply(marketParams(), assets, 0, address(this), hex"");
    }

    function _withdraw(address caller, address receiver, address owner, uint256 assets, uint256 shares)
        internal
        override
    {
        MORPHO.withdraw(marketParams(), assets, 0, address(this), address(this));
        super._withdraw(caller, receiver, owner, assets, shares);
    }
}
