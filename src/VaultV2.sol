// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.28;

import {ERC20, IERC20} from "../lib/openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";
import {Math} from "../lib/openzeppelin-contracts/contracts/utils/math/Math.sol";
import {SafeERC20} from "../lib/openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";

import {TimelockData, TimelockConfig, IMarket, IVaultV2} from "./interfaces/IVaultV2.sol";
import {IIRM} from "./interfaces/IIRM.sol";
import {IAllocator} from "./interfaces/IAllocator.sol";

import {ErrorsLib} from "./libraries/ErrorsLib.sol";

contract VaultV2 is ERC20, IVaultV2 {
    using Math for uint256;

    /* IMMUTABLE */

    IERC20 public immutable asset;

    /* TRANSIENT */

    bool public unlocked;

    /* STORAGE */

    // Note that each role could be a smart contract: the owner, curator and allocator.
    // This way, roles are modularized, and notably restricting their capabilities could be done on top.
    address public owner;
    address public curator;
    address public guardian;
    IAllocator public allocator;

    IIRM public irm;
    uint256 public lastUpdate;
    uint256 public lastTotalAssets;

    mapping(address => uint160) public cap;

    mapping(uint256 => TimelockData) public timelockData;
    mapping(bytes4 => TimelockConfig) public timelockConfig;
    // Can be made much more efficient, storing it all in one slot that does not get reset.
    uint256 internal pendingTimelocks;
    uint256 internal maxTimelock;

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
            (bool success, bytes memory data) = address(this).delegatecall(bundle[i]);
            if (!success) {
                assembly {
                    revert(add(data, 32), mload(data))
                }
            }
        }

        unlocked = false;
    }

    /* ONWER ACTIONS */

    function submitOwner(address newOwner) external {
        require(msg.sender == owner, ErrorsLib.Unauthorized());

        submit(IVaultV2.submitOwner.selector, 5, uint160(owner), uint160(newOwner));
    }

    function acceptOwner() external {
        require(timelockData[5].validAt != 0, ErrorsLib.TimelockNotSet());
        require(block.timestamp >= timelockData[5].validAt, ErrorsLib.TimelockNotExpired());

        owner = address(timelockData[5].value);
    }

    function submitCurator(address newCurator) external {
        require(msg.sender == owner, ErrorsLib.Unauthorized());

        submit(IVaultV2.submitCurator.selector, 6, uint160(curator), uint160(newCurator));
    }

    function acceptCurator() external {
        require(timelockData[6].validAt != 0, ErrorsLib.TimelockNotSet());
        require(block.timestamp >= timelockData[6].validAt, ErrorsLib.TimelockNotExpired());

        curator = address(timelockData[6].value);
    }

    function submitGuardian(address newGuardian) external {
        require(msg.sender == owner, ErrorsLib.Unauthorized());

        submit(IVaultV2.submitGuardian.selector, 7, uint160(guardian), uint160(newGuardian));
    }

    function acceptGuardian() external {
        require(timelockData[7].validAt != 0, ErrorsLib.TimelockNotSet());
        require(block.timestamp >= timelockData[7].validAt, ErrorsLib.TimelockNotExpired());

        guardian = address(timelockData[7].value);
    }

    function submitTimelock(bytes4 id, TimelockConfig memory config) external {
        require(msg.sender == owner, ErrorsLib.Unauthorized());
        require(pendingTimelocks == 0, ErrorsLib.TimelockPending());
        require(config.timelockToUnzero >= maxTimelock, ErrorsLib.SmallerThanMaxTimelock());
        require(config.timelockToIncrease >= maxTimelock, ErrorsLib.SmallerThanMaxTimelock());
        require(config.timelockToDecrease >= maxTimelock, ErrorsLib.SmallerThanMaxTimelock());

        uint160 oldValue = uint160(timelockConfig[id].timelockToUnzero)
            | (uint160(timelockConfig[id].timelockToIncrease) << 32)
            | (uint160(timelockConfig[id].timelockToDecrease) << 64);
        uint160 newValue = uint160(config.timelockToUnzero) | (uint160(config.timelockToIncrease) << 32)
            | (uint160(config.timelockToDecrease) << 64);

        uint256 slot = uint256(keccak256(abi.encode(id, 14)));
        submit(IVaultV2.submitTimelock.selector, slot, oldValue, newValue);
    }

    function acceptTimelock(bytes4 id) external {
        require(timelockData[uint256(keccak256(abi.encode(id, 14)))].validAt != 0, ErrorsLib.TimelockNotSet());
        require(
            block.timestamp >= timelockData[uint256(keccak256(abi.encode(id, 14)))].validAt,
            ErrorsLib.TimelockNotExpired()
        );

        TimelockConfig memory config;
        uint256 value = uint256(timelockData[uint256(keccak256(abi.encode(id, 14)))].value);
        config.timelockToUnzero = uint32(value);
        config.timelockToIncrease = uint32(value >> 32);
        config.timelockToDecrease = uint32(value >> 64);

        timelockConfig[id] = config;
    }

    /* CURATOR ACTIONS */

    function submitAllocator(address newAllocator) external {
        require(msg.sender == curator, ErrorsLib.Unauthorized());

        submit(IVaultV2.submitAllocator.selector, 8, uint160(address(allocator)), uint160(newAllocator));
    }

    function acceptAllocator() external {
        require(timelockData[8].validAt != 0, ErrorsLib.TimelockNotSet());
        require(block.timestamp >= timelockData[8].validAt, ErrorsLib.TimelockNotExpired());

        allocator = IAllocator(address(timelockData[8].value));
    }

    function submitCap(address market, uint160 newCap) external {
        require(msg.sender == curator, ErrorsLib.Unauthorized());

        uint256 slot = uint256(keccak256(abi.encode(market, 12)));
        submit(IVaultV2.submitCap.selector, slot, cap[market], newCap);
    }

    function acceptCap(address market) external {
        require(timelockData[uint256(keccak256(abi.encode(market, 12)))].validAt != 0, ErrorsLib.TimelockNotSet());
        require(
            block.timestamp >= timelockData[uint256(keccak256(abi.encode(market, 12)))].validAt,
            ErrorsLib.TimelockNotExpired()
        );

        cap[market] = uint160(timelockData[uint256(keccak256(abi.encode(market, 12)))].value);
    }

    function submitIRM(address newIRM) external {
        require(msg.sender == curator, ErrorsLib.Unauthorized());

        submit(IVaultV2.submitIRM.selector, 9, uint160(address(irm)), uint160(newIRM));
    }

    function acceptIRM() external {
        require(timelockData[9].validAt != 0, ErrorsLib.TimelockNotSet());
        require(block.timestamp >= timelockData[9].validAt, ErrorsLib.TimelockNotExpired());

        irm = IIRM(address(timelockData[9].value));
    }

    /* TIMELOCKS */

    function submit(bytes4 id, uint256 slot, uint160 oldValue, uint160 newValue) internal {
        if (oldValue == 0) {
            timelockData[slot].validAt = uint64(block.timestamp) + timelockConfig[id].timelockToUnzero;
        } else if (newValue > oldValue) {
            timelockData[slot].validAt = uint64(block.timestamp) + timelockConfig[id].timelockToIncrease;
        } else {
            timelockData[slot].validAt = uint64(block.timestamp) + timelockConfig[id].timelockToDecrease;
        }

        timelockData[slot].value = newValue;
        pendingTimelocks++;
    }

    function revoke(uint256 slot) external {
        require(msg.sender == guardian, ErrorsLib.Unauthorized());

        delete timelockData[slot];
        pendingTimelocks--;
    }

    /* ALLOCATOR ACTIONS */

    // Note how the discrepancy between transferred amount and increase in market.totalAssets() is handled:
    // it is not reflected in vault.totalAssets() but will have an impact on interest.
    function reallocateFromIdle(address market, uint256 amount) external {
        require(unlocked, ErrorsLib.Locked());
        asset.approve(market, amount);
        // Interest accrual can make the supplied amount go over the cap.
        require(amount + IMarket(market).balanceOf(address(this)) <= cap[address(market)], ErrorsLib.CapExceeded());
        IMarket(market).deposit(amount, address(this));
    }

    // Note how the discrepancy between transferred amount and decrease in market.totalAssets() is handled:
    // it is not reflected in vault.totalAssets() but will have an impact on interest.
    function reallocateToIdle(address market, uint256 amount) external {
        require(unlocked, ErrorsLib.Locked());
        IMarket(market).withdraw(amount, address(this), address(this));
    }

    /* EXCHANGE RATE */

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

    /* INTERFACE */

    function balanceOf(address user) public view override(ERC20, IMarket) returns (uint256) {
        return super.balanceOf(user);
    }

    function maxWithdraw(address) external view returns (uint256) {
        return asset.balanceOf(address(this));
    }
}
