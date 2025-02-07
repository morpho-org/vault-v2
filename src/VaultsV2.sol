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

    error UnauthorizedMulticall();

    /* STORAGE */

    // Note that the owner could be a smart contract, so that it is restricted in what it does.
    // In that sense the owner is modularized.
    // Notably, the owner could be restricted in what it can call, and choices it makes could be decentralized.
    address public owner;

    // Note that the curator could be a smart contract, so that it is restricted in what it does.
    // In that sense the curator is modularized.
    // Notably, the curator could be restricted in what it can call, and choices it makes could be decentralized.
    ICurator public curator;

    IERC20 public asset;
    IIRM public irm;
    uint256 public lastUpdate;
    uint256 public lastTotalAssets;
    IERC4626[] public markets;

    // keccak256(abi.encode(uint256(keccak256("morpho.vaultsV2.unlocked")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 constant UNLOCKED_SLOT = 0x99ba1fe4c6889aab9c8272f5ca5958d5dedb1cd5c4a03616899e55505bf76900;

    function unlocked() internal view returns (bool isUnlocked) {
        assembly ("memory-safe") {
            isUnlocked := tload(UNLOCKED_SLOT)
        }
    }

    function setUnlock(bool unlock) internal {
        assembly ("memory-safe") {
            tstore(UNLOCKED_SLOT, unlock)
        }
    }

    /* CONSTRUCTOR */

    constructor(address _curator, address _owner, address _asset, string memory _name, string memory _symbol)
        ERC20(_name, _symbol)
    {
        curator = ICurator(_curator);
        owner = _owner;
        asset = IERC20(_asset);
        lastUpdate = block.timestamp;
    }

    /* AUTHORIZED MULTICALL */

    function multiCall(bytes[] calldata bundle) external {
        // Could also make it ok in case msg.sender == curator, to optimize admin calls.
        curator.authorizeMulticall(msg.sender, bundle);

        // Is this safe with reentrant calls ?
        setUnlock(true);

        for (uint256 i = 0; i < bundle.length; i++) {
            // Note: no need to check that address(this) has code.
            (bool success,) = address(this).delegatecall(bundle[i]);
            require(success);
        }

        setUnlock(false);
    }

    /* EMERGENCY */

    // Can be seen as an exit to underlying, governed by the owner.
    function takeOwnership(ICurator newCurator) external {
        require(msg.sender == owner);
        // No need to set newCurator as an immutable of the vault, as it could be done in the owner.
        curator = newCurator;
        owner = address(0);
        irm = IIRM(address(0));
    }

    /* INTEREST MANAGEMENT */

    function setIRM(address _irm) external {
        require(unlocked());
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
    // TODO: make it more realistic, as it should be estimated from the interest per second returned by the markets.
    function realInterestPerSecond() public pure returns (int256) {
        return int256(5 ether) / 365 days;
    }

    /* ALLOCATION */

    function enableNewMarket(address market) external {
        require(unlocked());
        asset.approve(market, type(uint256).max);
        markets.push(IERC4626(market));
    }

    // Note how the discrepancy between transferred amount and increase in market.totalAssets() is handled:
    // it is not reflected in vault.totalAssets() but will have an impact on interest.
    function reallocateFromIdle(uint256 marketIndex, uint256 amount) external {
        require(unlocked());
        IERC4626 market = markets[marketIndex];
        market.deposit(amount, address(this));
    }

    // Note how the discrepancy between transferred amount and decrease in market.totalAssets() is handled:
    // it is not reflected in vault.totalAssets() but will have an impact on interest.
    function reallocateToIdle(uint256 marketIndex, uint256 amount) external {
        require(unlocked());
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
        assets = convertToAssets(shares, Math.Rounding.Floor);
        _withdraw(assets, shares, receiver, supplier);
    }
}
