// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.27;

import {
    IERC4626,
    ERC20,
    IERC20,
    SafeERC20,
    Math
} from "../lib/openzeppelin-contracts/contracts/token/ERC20/extensions/ERC4626.sol";

import {WAD, IVaultsV2} from "./interfaces/IVaultsV2.sol";
import {IIRM} from "./interfaces/IIRM.sol";

// TODO: implement an ErrorsLib
contract VaultsV2 is ERC20, IVaultsV2 {
    using Math for uint256;
    /* IMMUTABLE */

    address public immutable guardian;

    /* STORAGE */

    // TODO: owner could actually be made immutable.
    address public owner;
    IERC20 asset;
    uint256 public lastUpdate;
    uint256 public lastTotalAssets;
    IIRM public irm;
    IERC4626[] public markets;

    /* CONSTRUCTOR */

    constructor(address _guardian, address _asset, string memory _name, string memory _symbol) ERC20(_name, _symbol) {
        owner = msg.sender;
        guardian = _guardian;
        asset = IERC20(_asset);
    }

    /* EMERGENCY */

    // Can be seen as an exit to underlying, governed by the guardian.
    // TODO: restrict guardian more to have better guarantees.
    function disown() external {
        require(msg.sender == guardian);
        owner = guardian;
    }

    /* EXCHANGE RATE */

    function totalAssets() public view returns (uint256) {
        // TODO: could virtually accrue here instead, which would be more precise.
        return lastTotalAssets;
    }

    // TODO: compound rate, instead of having a linear interest rate.
    function accrueInterest() public {
        uint256 elapsed = block.timestamp - lastUpdate;
        // Note that rate could be negative, but this is not always incentive compatible.
        lastTotalAssets *= WAD + irm.rate() * elapsed;
        lastUpdate = block.timestamp;
    }

    // TODO: extract virtual shares and assets.
    function convertToShares(uint256 assets, Math.Rounding rounding) internal view returns (uint256 shares) {
        shares = assets.mulDiv(totalSupply() + 1, lastTotalAssets + 1, rounding);
    }

    function convertToAssets(uint256 shares, Math.Rounding rounding) internal view returns (uint256 assets) {
        shares = assets.mulDiv(lastTotalAssets + 1, totalSupply() + 1, rounding);
    }

    // To override to take custody and manage funds.
    function realAssets() public virtual returns (uint256) {
        return totalAssets();
    }

    /* USER INTERACTION */

    function _deposit(address receiver, uint256 assets, uint256 shares) internal {
        SafeERC20.safeTransferFrom(asset, msg.sender, address(this), assets);
        _mint(receiver, shares);
    }

    function deposit(uint256 assets, address receiver) public virtual returns (uint256 shares) {
        accrueInterest();
        // Note that it could be made more efficient by caching lastTotalAssets.
        shares = convertToShares(assets, Math.Rounding.Floor);
        _deposit(receiver, assets, shares);
        lastTotalAssets += assets;
        lastUpdate = block.timestamp;
    }

    function mint(uint256 shares, address receiver) public virtual returns (uint256 assets) {
        accrueInterest();
        assets = convertToAssets(shares, Math.Rounding.Ceil);
        _deposit(receiver, assets, shares);
        lastTotalAssets += assets;
        lastUpdate = block.timestamp;
    }

    function _withdraw(address receiver, address _owner, uint256 assets, uint256 shares) internal virtual {
        if (msg.sender != _owner) _spendAllowance(_owner, msg.sender, shares);
        _burn(owner, shares);
        SafeERC20.safeTransfer(asset, receiver, assets);
    }

    function withdraw(uint256 assets, address receiver, address _owner) public virtual returns (uint256 shares) {
        accrueInterest();
        shares = convertToShares(assets, Math.Rounding.Ceil);
        _withdraw(receiver, _owner, assets, shares);
        lastTotalAssets -= assets;
        lastUpdate = block.timestamp;
    }

    function redeem(uint256 shares, address receiver, address _owner) public virtual returns (uint256 assets) {
        accrueInterest();
        assets = convertToAssets(shares, Math.Rounding.Floor);
        _withdraw(receiver, _owner, assets, shares);
        lastTotalAssets -= assets;
        lastUpdate = block.timestamp;
    }

    /* ALLOCATION */
}
