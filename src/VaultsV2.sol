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
import {ICurator} from "./interfaces/ICurator.sol";

// TODO: implement an ErrorsLib.
// TODO: inherit from a dedicated interface (IVaultsV2).
contract VaultsV2 is ERC20 {
    using Math for uint256;

    /* STORAGE */

    // Note that the guardian could be a smart contract, so that it is restricted in what it does.
    // In that sense the guardian is modularized.
    // Notably, the guardian could be restricted in what it can call, and choices it makes could be decentralized.
    address public guardian;

    // Note that the curator could be a smart contract, so that it is restricted in what it does.
    // In that sense the curator is modularized.
    // Notably, the curator could be restricted in what it can call, and choices it makes could be decentralized.
    ICurator public curator;

    IERC20 public asset;
    IIRM public irm;
    uint256 public lastUpdate;
    uint256 public lastTotalAssets;
    IERC4626[] public markets;

    // TODO: optimize this with transient storage.
    bool public unlocked;

    /* CONSTRUCTOR */

    constructor(address _curator, address _guardian, address _asset, string memory _name, string memory _symbol)
        ERC20(_name, _symbol)
    {
        curator = ICurator(_curator);
        guardian = _guardian;
        asset = IERC20(_asset);
        lastUpdate = block.timestamp;
    }

    /* AUTHORIZED MULTICALL */

    function multiCall(bytes[] calldata bundle) external {
        // Could also make it ok in case msg.sender == curator, to optimize admin calls.
        require(curator.authorizedMulticall(msg.sender, bundle));

        // Is this safe with reentrant calls ?
        unlocked = true;

        for (uint256 i = 0; i < bundle.length; i++) {
            // Note: no need to check that address(this) has code.
            (bool success,) = address(this).delegatecall(bundle[i]);
            require(success);
        }

        unlocked = false;
    }

    /* EMERGENCY */

    // Can be seen as an exit to underlying, governed by the guardian.
    function takeOwnership(ICurator newCurator) external {
        require(msg.sender == guardian);
        // No need to set newCurator as an immutable of the vault, as it could be done in the guardian.
        curator = newCurator;
        guardian = address(0);
        irm = IIRM(address(0));
    }

    /* INTEREST MANAGEMENT */

    function setIRM(address _irm) external {
        require(unlocked);
        irm = IIRM(_irm);
    }

    // Vault managers would not use this function when taking full custody.
    // Note that donations would be smoothed, which is a nice feature to incentivize the vault directly.
    function realAssets() public view returns (uint256 aum) {
        aum = asset.balanceOf(address(this));
        for (uint256 i; i < markets.length; i++) {
            aum += markets[i].convertToAssets(markets[i].balanceOf(address(this)));
        }
    }

    // Vault managers would not use this function when taking full custody.
    // TODO: make it more realistic, as it should be estimated from the interest per second returned by the markets
    // themselves.
    function realInterestPerSecond() public pure returns (int256) {
        return int256(5 ether) / 365 days;
    }

    /* ALLOCATION */

    function enableNewMarket(IERC4626 market) external {
        require(unlocked);
        asset.approve(address(market), type(uint256).max);
        markets.push(market);
    }

    // Note how the discrepancy between transferred amount and increase in market.totalAssets() is handled:
    // it is not reflected in vault.totalAssets() but will have an impact on interest.
    function reallocateFromIdle(uint256 marketIndex, uint256 amount) external {
        require(unlocked);
        IERC4626 market = markets[marketIndex];
        market.deposit(amount, address(this));
    }

    // Note how the discrepancy between transferred amount and decrease in market.totalAssets() is handled:
    // it is not reflected in vault.totalAssets() but will have an impact on interest.
    function reallocateToIdle(uint256 marketIndex, uint256 amount) external {
        require(unlocked);
        IERC4626 market = markets[marketIndex];
        market.withdraw(amount, address(this), address(this));
    }

    /* EXCHANGE RATE */

    function totalAssets() public view returns (uint256) {
        // TODO: virtually accrue here instead, which would be more precise.
        return lastTotalAssets;
    }

    function accrueInterest() public {
        uint256 elapsed = block.timestamp - lastUpdate;
        // Note that interest could be negative, but this is not always incentive compatible: users would want to leave.
        // But keeping this possible still, as it can make sense in the custody case when withdrawals are disabled.
        // Note that interestPerSecond should probably be bounded to give guarantees that it cannot rug users instantly.
        // Note that irm.interestPerSecond() reverts if the vault is not initialized and has irm == address(0).
        int256 newTotalAssets = int256(lastTotalAssets) + irm.interestPerSecond() * int256(elapsed);
        lastTotalAssets = newTotalAssets >= 0 ? uint256(newTotalAssets) : 0;
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

    function _deposit(uint256 assets, uint256 shares, address receiver) internal {
        SafeERC20.safeTransferFrom(asset, msg.sender, address(this), assets);
        _mint(receiver, shares);
        lastTotalAssets += assets;
    }

    // TODO: how to hook on deposit so that assets are atomically allocated ?
    function deposit(uint256 assets, address receiver) public virtual returns (uint256 shares) {
        accrueInterest();
        // Note that it could be made more efficient by caching lastTotalAssets.
        shares = convertToShares(assets, Math.Rounding.Floor);
        _deposit(assets, shares, receiver);
    }

    function mint(uint256 shares, address receiver) public virtual returns (uint256 assets) {
        accrueInterest();
        assets = convertToAssets(shares, Math.Rounding.Ceil);
        _deposit(assets, shares, receiver);
    }

    function _withdraw(uint256 assets, uint256 shares, address receiver, address owner) internal virtual {
        if (msg.sender != owner) _spendAllowance(owner, msg.sender, shares);
        _burn(owner, shares);
        SafeERC20.safeTransfer(asset, receiver, assets);
        lastTotalAssets -= assets;
    }

    // Note that it is not callable by default, if there is no liquidity.
    // This is actually a feature, so that the curator can pause withdrawals if necessary/wanted.
    function withdraw(uint256 assets, address receiver, address owner) public virtual returns (uint256 shares) {
        accrueInterest();
        shares = convertToShares(assets, Math.Rounding.Ceil);
        _withdraw(assets, shares, receiver, owner);
    }

    function redeem(uint256 shares, address receiver, address owner) public virtual returns (uint256 assets) {
        accrueInterest();
        assets = convertToAssets(shares, Math.Rounding.Floor);
        _withdraw(assets, shares, receiver, owner);
    }
}
