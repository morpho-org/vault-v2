// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.28;

import {ERC20, IERC20} from "../lib/openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";
import {Math} from "../lib/openzeppelin-contracts/contracts/utils/math/Math.sol";
import {SafeERC20} from "../lib/openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";

import {WAD, IMarket} from "./interfaces/IMarket.sol";
import {IIRM} from "./interfaces/IIRM.sol";
import {IAllocator} from "./interfaces/IAllocator.sol";
import {ErrorsLib} from "./libraries/ErrorsLib.sol";

contract VaultsV2 is ERC20, IMarket {
    using Math for uint256;

    /* IMMUTABLE */

    IERC20 public immutable asset;

    /* STORAGE */

    // Note that each role could be a smart contract: the owner, curator and allocator.
    // This way, roles are modularized, and notably restricting their capabilities could be done on top.
    address public owner;
    address public curator;
    IAllocator public allocator;

    IIRM public irm;
    uint256 public lastUpdate;
    uint256 public lastTotalAssets;

    IMarket[] public markets;

    /* TRANSIENT */

    bool public transient unlocked;

    /* CONSTRUCTOR */

    constructor(
        address _owner,
        address _curator,
        address _allocator,
        address _asset,
        string memory _name,
        string memory _symbol
    ) ERC20(_name, _symbol) {
        owner = _owner;
        curator = _curator;
        allocator = IAllocator(_allocator);
        owner = _owner;
        asset = IERC20(_asset);
        lastUpdate = block.timestamp;
    }

    /* AUTHORIZED MULTICALL */

    function multicall(bytes[] calldata bundle) external {
        allocator.authorizeMulticall(msg.sender, bundle);

        // Is this safe with reentrant calls ?
        unlocked = true;

        for (uint256 i = 0; i < bundle.length; i++) {
            // Note: no need to check that address(this) has code.
            (bool success,) = address(this).delegatecall(bundle[i]);
            require(success, ErrorsLib.FailedDelegateCall());
        }

        unlocked = false;
    }

    /* ONWER ACTIONS */

    function setOwner(address newOwner) external {
        require(msg.sender == owner, ErrorsLib.Unautorized());
        curator = newOwner;
    }

    // Can be seen as an exit to underlying, governed by the owner.
    function setCurator(address newCurator) external {
        require(msg.sender == owner, ErrorsLib.Unautorized());
        // No need to set newCurator as an immutable of the vault, as it could be done in the owner.
        curator = newCurator;
    }

    /* CURATOR ACTIONS */

    function setAllocator(address newAllocator) external {
        require(msg.sender == curator || msg.sender == address(allocator), ErrorsLib.Unautorized());
        allocator = IAllocator(newAllocator);
    }

    function newMarket(address market) external {
        require(msg.sender == curator, ErrorsLib.Unautorized());
        asset.approve(market, type(uint256).max);
        markets.push(IMarket(market));
    }

    function dropMarket(uint256 index) external {
        require(msg.sender == curator, ErrorsLib.Unautorized());
        asset.approve(address(markets[index]), 0);
        IMarket lastMarket = markets[markets.length - 1];
        markets.pop();
        markets[index] = lastMarket;
    }

    function setIRM(address _irm) external {
        require(msg.sender == curator, ErrorsLib.Unautorized());
        irm = IIRM(_irm);
    }

    /* ALLOCATOR ACTIONS */

    // Note how the discrepancy between transferred amount and increase in market.totalAssets() is handled:
    // it is not reflected in vault.totalAssets() but will have an impact on interest.
    function reallocateFromIdle(uint256 marketIndex, uint256 amount) external {
        require(unlocked, ErrorsLib.Locked());
        IMarket market = markets[marketIndex];
        market.deposit(amount, address(this));
    }

    // Note how the discrepancy between transferred amount and decrease in market.totalAssets() is handled:
    // it is not reflected in vault.totalAssets() but will have an impact on interest.
    function reallocateToIdle(uint256 marketIndex, uint256 amount) external {
        require(unlocked, ErrorsLib.Locked());
        IMarket market = markets[marketIndex];
        market.withdraw(amount, address(this), address(this));
    }

    /* EXCHANGE RATE */

    // Vault managers would not use this function when taking full custody.
    // Note that donations would be smoothed, which is a nice feature to incentivize the vault directly.
    function realAssets() external view returns (uint256 aum) {
        aum = asset.balanceOf(address(this));
        for (uint256 i; i < markets.length; i++) {
            aum += markets[i].convertToAssets(markets[i].balanceOf(address(this)));
        }
    }

    function totalAssets() public view returns (uint256) {
        return _accruedInterest();
    }

    function accrueInterest() public {
        lastTotalAssets = _accruedInterest();
        lastUpdate = block.timestamp;
    }

    function _accruedInterest() internal view returns (uint256) {
        uint256 elapsed = block.timestamp - lastUpdate;
        // Note that interest could be negative, but this is not always incentive compatible: users would want to leave.
        // But keeping this possible still, as it can make sense in the custody case when withdrawals are disabled.
        // Note that interestPerSecond should probably be bounded to give guarantees that it cannot rug users instantly.
        // Note that irm.interestPerSecond() reverts if the vault is not initialized and has irm == address(0).
        int256 newTotalAssets = int256(lastTotalAssets) + irm.interestPerSecond() * int256(elapsed);
        return newTotalAssets >= 0 ? uint256(newTotalAssets) : 0;
    }

    // TODO: extract virtual shares and assets (= 1).
    function convertToShares(uint256 assets, Math.Rounding rounding) public view returns (uint256 shares) {
        shares = assets.mulDiv(totalSupply() + 1, lastTotalAssets + 1, rounding);
    }

    function convertToAssets(uint256 shares, Math.Rounding rounding) public view returns (uint256 assets) {
        assets = shares.mulDiv(lastTotalAssets + 1, totalSupply() + 1, rounding);
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
        assets = convertToShares(shares, Math.Rounding.Ceil);
        _deposit(assets, shares, receiver);
    }

    function _withdraw(uint256 assets, uint256 shares, address receiver, address supplier) internal virtual {
        if (msg.sender != supplier) _spendAllowance(supplier, msg.sender, shares);
        _burn(supplier, shares);
        SafeERC20.safeTransfer(asset, receiver, assets);
        lastTotalAssets -= assets;
    }

    // Note that it is not callable by default, if there is no liquidity.
    // This is actually a feature, so that the curator can pause withdrawals if necessary/wanted.
    function withdraw(uint256 assets, address receiver, address supplier) public virtual returns (uint256 shares) {
        accrueInterest();
        shares = convertToShares(assets, Math.Rounding.Ceil);
        _withdraw(assets, shares, receiver, supplier);
    }

    function redeem(uint256 shares, address receiver, address supplier) public virtual returns (uint256 assets) {
        accrueInterest();
        assets = convertToShares(shares, Math.Rounding.Floor);
        _withdraw(assets, shares, receiver, supplier);
    }

    function balanceOf(address user) public view override(ERC20, IMarket) returns(uint256) {
        return super.balanceOf(user);
    }
}
