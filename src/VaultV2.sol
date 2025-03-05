// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.28;

import {ERC20, IERC20} from "../lib/openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";
import {Math} from "../lib/openzeppelin-contracts/contracts/utils/math/Math.sol";
import {SafeERC20} from "../lib/openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";

import {TimelockData, IMarket, IVaultV2} from "./interfaces/IVaultV2.sol";
import {IIRM} from "./interfaces/IIRM.sol";
import {IAllocator} from "./interfaces/IAllocator.sol";

import {ErrorsLib} from "./libraries/ErrorsLib.sol";

contract VaultV2 is ERC20, IVaultV2 {
    using Math for uint256;

    /* IMMUTABLE */

    IERC20 public immutable asset;

    /* TRANSIENT */

    // TODO: make this actually transient.
    bool public unlocked;

    /* STORAGE */

    // Note that each role could be a smart contract: the owner, curator and allocator.
    // This way, roles are modularized, and notably restricting their capabilities could be done on top.
    address public owner;
    address public curator;
    IAllocator public allocator;
    address public guardian;

    IIRM public irm;
    uint256 public lastUpdate;
    uint256 public lastTotalAssets;

    IMarket[] public markets;
    mapping(address => uint160) public cap;

    mapping(bytes24 => TimelockData) public timelockData;
    mapping(bytes4 => uint64) public timelockDuration;
    // Can be made more efficient by not resetting the slot.
    uint256 internal pendingTimelocksCount;

    /* CONSTRUCTOR */

    constructor(
        address _owner,
        address _curator,
        address _allocator,
        address _asset,
        string memory _name,
        string memory _symbol
    ) ERC20(_name, _symbol) {
        asset = IERC20(_asset);
        owner = _owner;
        curator = _curator;
        allocator = IAllocator(_allocator);
        lastUpdate = block.timestamp;
        // The vault starts with no IRM, no markets and no assets. To be configured afterwards.
    }

    /* AUTHORIZED MULTICALL */

    function multicall(bytes[] calldata bundle) external {
        allocator.authorizeMulticall(msg.sender, bundle);

        // The allocator is responsible for making sure that bundles cannot reenter.
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
        require(msg.sender == owner, ErrorsLib.Unauthorized());
        uint160 serializedNewValue = uint160(newOwner);
        if (submittedToTimelock(serializedNewValue)) owner = newOwner;
    }

    // Can be seen as an exit to underlying, governed by the owner.
    function setCurator(address newCurator) external {
        require(msg.sender == owner, ErrorsLib.Unauthorized());
        uint160 serializedNewValue = uint160(newCurator);
        if (submittedToTimelock(serializedNewValue)) curator = newCurator;
    }

    function setGuardian(address newGuardian) external {
        require(msg.sender == owner, ErrorsLib.Unauthorized());
        uint160 serializedNewValue = uint160(newGuardian);
        if (submittedToTimelock(serializedNewValue)) owner = newGuardian;
    }

    /* CURATOR ACTIONS */

    function setAllocator(address newAllocator) external {
        require(msg.sender == owner || msg.sender == address(allocator), ErrorsLib.Unauthorized());
        uint160 serializedNewValue = uint160(newAllocator);
        if (submittedToTimelock(serializedNewValue)) allocator = IAllocator(newAllocator);
    }

    // Could set cap right when adding a market, to avoid having to wait the timelock twice.
    function newMarket(address market) external {
        require(msg.sender == curator, ErrorsLib.Unauthorized());
        uint160 serializedNewValue = uint160(market);
        if (submittedToTimelock(serializedNewValue, serializedNewValue)) {
            asset.approve(market, type(uint256).max);
            markets.push(IMarket(market));
        }
    }

    function dropMarket(uint8 index) external {
        require(msg.sender == curator, ErrorsLib.Unauthorized());
        address market = address(markets[index]);
        uint160 serializedNewValue = uint160(market);
        if (submittedToTimelock(serializedNewValue, serializedNewValue)) {
            asset.approve(market, 0);
            markets[index] = markets[markets.length - 1];
            markets.pop();
        }
    }

    function setCap(address market, uint160 newCap) external {
        require(msg.sender == curator, ErrorsLib.Unauthorized());
        uint160 serializedNewValue = type(uint160).max - newCap;
        if (newCap < cap[market] || submittedToTimelock(uint160(market), serializedNewValue)) {
            cap[market] = newCap;
        }
    }

    function setIRM(address newIRM) external {
        require(msg.sender == curator, ErrorsLib.Unauthorized());
        uint160 serializedNewValue = uint160(newIRM);
        if (submittedToTimelock(serializedNewValue)) irm = IIRM(newIRM);
    }

    /* ALLOCATOR ACTIONS */

    // Note how the discrepancy between transferred amount and increase in market.totalAssets() is handled:
    // it is not reflected in vault.totalAssets() but will have an impact on interest.
    function reallocateFromIdle(uint256 marketIndex, uint256 amount) external {
        require(unlocked, ErrorsLib.Locked());
        IMarket market = markets[marketIndex];
        // Interest accrual can make the supplied amount go over the cap.
        require(amount + market.balanceOf(address(this)) <= cap[address(market)], ErrorsLib.CapExceeded());
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

    function convertToShares(uint256 assets) external view returns (uint256) {
        return convertToShares(assets, Math.Rounding.Floor);
    }

    // TODO: extract virtual shares and assets (= 1).
    function convertToShares(uint256 assets, Math.Rounding rounding) internal view returns (uint256 shares) {
        shares = assets.mulDiv(totalSupply() + 1, lastTotalAssets + 1, rounding);
    }

    function convertToAssets(uint256 shares) external view returns (uint256) {
        return convertToAssets(shares, Math.Rounding.Floor);
    }

    function convertToAssets(uint256 shares, Math.Rounding rounding) internal view returns (uint256 assets) {
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

    /* TIMELOCKS */

    function maxTimelockDuration() internal view returns (uint256 max) {
        bytes4[8] memory selectorsList = [
            IVaultV2.setOwner.selector,
            IVaultV2.setCurator.selector,
            IVaultV2.setGuardian.selector,
            IVaultV2.setAllocator.selector,
            IVaultV2.newMarket.selector,
            IVaultV2.dropMarket.selector,
            IVaultV2.setCap.selector,
            IVaultV2.setIRM.selector
        ];
        for (uint256 i; i < 8; i++) {
            bytes4 sel = selectorsList[i];
            uint256 currentDuration = timelockDuration[sel];
            max = currentDuration > max ? currentDuration : max;
        }
    }

    function setTimelock(bytes4 sel, uint64 newDuration) external {
        require(msg.sender == curator, ErrorsLib.Unauthorized());
        bool greaterThanOtherTimelocks = sel == IVaultV2.setTimelock.selector
            ? newDuration >= maxTimelockDuration()
            : newDuration <= timelockDuration[IVaultV2.setTimelock.selector];
        bool authorizedToSubmit =
            pendingTimelocksCount == 0 && timelockData[sel].validAt == 0 && greaterThanOtherTimelocks;
        require(authorizedToSubmit);
        if (submittedToTimelock(uint32(sel), newDuration)) {
            timelockDuration[sel] = newDuration;
        }
    }

    function submittedToTimelock(uint160 newValue) internal returns (bool) {
        return submittedToTimelock(0, newValue);
    }

    function submittedToTimelock(uint160 field, uint160 newValue) internal returns (bool) {
        bytes4 sel = bytes4(msg.data[:4]);
        bytes24 id = bytes24(abi.encodePacked(sel, field));
        if (timelockDuration[sel] == 0) {
            return true;
        } else if (timelockData[id].validAt != 0) {
            require(block.timestamp >= timelockData[id].validAt, ErrorsLib.TimelockNotExpired());
            require(newValue == timelockData[id].value, ErrorsLib.WrongValue());
            clearTimelock(sel);

            return true;
        } else {
            require(timelockData[IVaultV2.setTimelock.selector].validAt == 0, ErrorsLib.TimelockIsChanging());
            timelockData[id].validAt = uint64(block.timestamp) + timelockDuration[sel];
            timelockData[id].value = newValue;
            pendingTimelocksCount++;

            return false;
        }
    }

    function clearTimelock(bytes4 sel) internal {
        timelockData[sel].validAt = 0;
        timelockData[sel].value = 0;
        pendingTimelocksCount--;
    }

    function revokeTimelock(bytes4 sel) external {
        require(msg.sender == guardian, ErrorsLib.Unauthorized());
        require(timelockData[sel].validAt != 0);
        clearTimelock(sel);
    }

    /* INTERFACE */

    function balanceOf(address user) public view override(ERC20, IMarket) returns (uint256) {
        return super.balanceOf(user);
    }

    function maxWithdraw(address) external view returns (uint256) {
        return asset.balanceOf(address(this));
    }

    function marketsLength() external view returns (uint256) {
        return markets.length;
    }
}
