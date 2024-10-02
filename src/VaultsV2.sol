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

    // TODO: curator could actually be made immutable.
    address public curator;
    IERC20 asset;
    IIRM public irm;
    uint256 public lastUpdate;
    uint256 public lastTotalAssets;
    IERC4626[] public markets;

    /* CONSTRUCTOR */

    constructor(address _guardian, address _asset, string memory _name, string memory _symbol) ERC20(_name, _symbol) {
        curator = msg.sender;
        guardian = _guardian;
        asset = IERC20(_asset);
    }

    /* EMERGENCY */

    // Can be seen as an exit to underlying, governed by the guardian.
    // TODO: restrict guardian more to have better guarantees, notably after it has taken over.
    function disown() external {
        require(msg.sender == guardian);
        curator = guardian;
    }

    /* CURATOR FUNCTIONS */

    function setIRM(address _irm) external {
        require(msg.sender == curator);
        // Note that the following is error prone, especially in emergency situations (when the guardian takes over
        // notably).
        irm = IIRM(_irm);
    }

    /* EXCHANGE RATE */

    function totalAssets() public view returns (uint256) {
        // TODO: could virtually accrue here instead, which would be more precise.
        return lastTotalAssets;
    }

    // TODO: compound rate, instead of having a linear interest rate.
    function accrueInterest() public {
        uint256 elapsed = block.timestamp - lastUpdate;
        // Note that rate could be negative, but this is not always incentive compatible: users would want to leave. But
        // keeping this possible still, as it can make sense in the custody case when withdrawals are disabled.
        // Note that the rate should probably be bounded to give guarantees that it cannot rug users instantly.
        // Note that irm.rate() reverts if the vault is not initialized and has irm == address(0).
        lastTotalAssets *= WAD + irm.rate() * elapsed;
        lastUpdate = block.timestamp;
    }

    // TODO: extract virtual shares and assets (= 1).
    function convertToShares(uint256 assets, Math.Rounding rounding) internal view returns (uint256 shares) {
        shares = assets.mulDiv(totalSupply() + 1, lastTotalAssets + 1, rounding);
    }

    function convertToAssets(uint256 shares, Math.Rounding rounding) internal view returns (uint256 assets) {
        shares = assets.mulDiv(lastTotalAssets + 1, totalSupply() + 1, rounding);
    }

    /* USER INTERACTION */

    function _deposit(address receiver, uint256 assets, uint256 shares) internal {
        SafeERC20.safeTransferFrom(asset, msg.sender, address(this), assets);
        _mint(receiver, shares);
        lastTotalAssets += assets;
    }

    function deposit(uint256 assets, address receiver) public virtual returns (uint256 shares) {
        accrueInterest();
        // Note that it could be made more efficient by caching lastTotalAssets.
        shares = convertToShares(assets, Math.Rounding.Floor);
        _deposit(receiver, assets, shares);
    }

    function mint(uint256 shares, address receiver) public virtual returns (uint256 assets) {
        accrueInterest();
        assets = convertToAssets(shares, Math.Rounding.Ceil);
        _deposit(receiver, assets, shares);
    }

    function _withdraw(address receiver, address owner, uint256 assets, uint256 shares) internal virtual {
        if (msg.sender != owner) _spendAllowance(owner, msg.sender, shares);
        _burn(owner, shares);
        SafeERC20.safeTransfer(asset, receiver, assets);
        lastTotalAssets -= assets;
    }

    function withdraw(uint256 assets, address receiver, address owner) public virtual returns (uint256 shares) {
        accrueInterest();
        shares = convertToShares(assets, Math.Rounding.Ceil);
        _withdraw(receiver, owner, assets, shares);
    }

    function redeem(uint256 shares, address receiver, address from) public virtual returns (uint256 assets) {
        accrueInterest();
        assets = convertToAssets(shares, Math.Rounding.Floor);
        _withdraw(receiver, from, assets, shares);
    }

    /* RATE MANAGEMENT */

    // Vault managers would not use this function when taking full custody.
    function realAssets() public view returns (uint256 aum) {
        for (uint256 i; i < markets.length; i++) {
            aum += markets[i].totalAssets();
        }
    }

    // Vault managers would not use this function when taking full custody.
    // TODO: make it more realistic, as it should be estimated from the rates returned by the markets themselves.
    function realRate() public pure returns (uint256) {
        return uint256(5 ether) / 365 days;
    }
}
