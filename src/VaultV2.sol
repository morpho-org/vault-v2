// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.28;

import {ERC20, IERC20} from "../lib/openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";
import {Math} from "../lib/openzeppelin-contracts/contracts/utils/math/Math.sol";
import {SafeERC20} from "../lib/openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";

import {IVaultV2, IAdapter} from "./interfaces/IVaultV2.sol";
import {IIRM} from "./interfaces/IIRM.sol";
import {ProtocolFee, IVaultV2Factory} from "./interfaces/IVaultV2Factory.sol";

import {ErrorsLib} from "./libraries/ErrorsLib.sol";
import {WAD} from "./libraries/ConstantsLib.sol";
import {MathLib} from "./libraries/MathLib.sol";

contract VaultV2 is ERC20, IVaultV2 {
    using Math for uint256;
    using MathLib for uint256;

    /* CONSTANT */
    uint64 public constant TIMELOCK_CAP = 2 weeks;

    /* IMMUTABLE */

    address public immutable factory;
    IERC20 public immutable asset;

    /* TRANSIENT */

    // TODO: make this actually transient.
    bool public unlocked;

    /* STORAGE */

    // Note that each role could be a smart contract: the owner, curator and guardian.
    // This way, roles are modularized, and notably restricting their capabilities could be done on top.
    address public owner;
    address public curator;
    address public treasurer;
    address public irm;
    mapping(address => bool) public isSentinel;
    mapping(address => bool) public isAllocator;

    /// @dev invariant: performanceFee != 0 => performanceFeeRecipient != address(0)
    uint256 public performanceFee;
    address public performanceFeeRecipient;
    /// @dev invariant: managementFee != 0 => managementFeeRecipient != address(0)
    uint256 public managementFee;
    address public managementFeeRecipient;

    uint256 public lastUpdate;
    uint256 public totalAssets;

    // Adapter is trusted to pass the expected ids when supplying assets.
    mapping(address => bool) public isAdapter;

    /// @dev Key is an abstract id, which can represent a protocol, a collateral, a duration etc.
    mapping(bytes32 => uint256) public absoluteCap;

    /// @dev Key is an abstract id, which can represent a protocol, a collateral, a duration etc.
    /// @dev Relative cap = 0 is interpreted as no relative cap.
    mapping(bytes32 => uint256) public relativeCap;

    /// @dev Useful to iterate over all ids with relative cap in withdrawals.
    bytes32[] public idsWithRelativeCap;

    /// @dev Interests are not counted in the allocation.
    /// @dev By design, double counting some stuff.
    mapping(bytes32 => uint256) public allocation;

    mapping(bytes => uint256) public validAt;
    mapping(bytes4 => uint64) public timelockDuration;

    /* CONSTRUCTOR */

    constructor(address _owner, address _asset, string memory _name, string memory _symbol) ERC20(_name, _symbol) {
        factory = msg.sender;
        asset = IERC20(_asset);
        owner = _owner;
        lastUpdate = block.timestamp;
        timelockDuration[IVaultV2.decreaseTimelock.selector] = TIMELOCK_CAP;
        // The vault starts with no IRM, no markets and no assets. To be configured afterwards.
    }

    /* OWNER ACTIONS */

    function setOwner(address newOwner) external timelocked {
        owner = newOwner;
    }

    function setCurator(address newCurator) external timelocked {
        curator = newCurator;
    }

    function setTreasurer(address newTreasurer) external timelocked {
        treasurer = newTreasurer;
    }

    function setIRM(address newIRM) external timelocked {
        irm = newIRM;
    }

    function setIsSentinel(address newSentinel, bool newIsSentinel) external timelocked {
        isSentinel[newSentinel] = newIsSentinel;
    }

    function setIsAllocator(address allocator, bool newIsAllocator) external timelocked {
        isAllocator[allocator] = newIsAllocator;
    }

    function setPerformanceFeeRecipient(address newPerformanceFeeRecipient) external timelocked {
        require(newPerformanceFeeRecipient != address(0) || performanceFee == 0, ErrorsLib.FeeInvariantBroken());

        performanceFeeRecipient = newPerformanceFeeRecipient;
    }

    function setManagementFeeRecipient(address newManagementFeeRecipient) external timelocked {
        require(newManagementFeeRecipient != address(0) || managementFee == 0, ErrorsLib.FeeInvariantBroken());

        managementFeeRecipient = newManagementFeeRecipient;
    }

    function setIsAdapter(address adapter, bool newIsAdapter) external timelocked {
        isAdapter[adapter] = newIsAdapter;
    }

    function increaseTimelock(bytes4 functionSelector, uint64 newDuration) external timelocked {
        require(functionSelector != IVaultV2.decreaseTimelock.selector, ErrorsLib.TimelockCapIsFixed());
        require(newDuration <= TIMELOCK_CAP, ErrorsLib.TimelockDurationTooHigh());
        require(newDuration > timelockDuration[functionSelector], ErrorsLib.TimelockNotIncreasing());

        timelockDuration[functionSelector] = newDuration;
    }

    function decreaseTimelock(bytes4 functionSelector, uint64 newDuration) external timelocked {
        require(functionSelector != IVaultV2.decreaseTimelock.selector, ErrorsLib.TimelockCapIsFixed());
        require(newDuration <= TIMELOCK_CAP, ErrorsLib.TimelockDurationTooHigh());
        require(newDuration < timelockDuration[functionSelector], ErrorsLib.TimelockNotDecreasing());

        timelockDuration[functionSelector] = newDuration;
    }

    /* TREASURER ACTIONS */

    function setPerformanceFee(uint256 newPerformanceFee) external timelocked {
        require(newPerformanceFee < WAD, ErrorsLib.FeeTooHigh());
        require(performanceFeeRecipient != address(0), ErrorsLib.FeeInvariantBroken());

        performanceFee = newPerformanceFee;
    }

    function setManagementFee(uint256 newManagementFee) external timelocked {
        require(newManagementFee < WAD, ErrorsLib.FeeTooHigh());
        require(managementFeeRecipient != address(0), ErrorsLib.FeeInvariantBroken());

        managementFee = newManagementFee;
    }

    /* CURATOR ACTIONS */

    function increaseAbsoluteCap(bytes32 id, uint256 newCap) external timelocked {
        require(newCap > absoluteCap[id], ErrorsLib.AbsoluteCapNotIncreasing());

        absoluteCap[id] = newCap;
    }

    function decreaseAbsoluteCap(bytes32 id, uint256 newCap) external timelocked {
        require(newCap < absoluteCap[id], ErrorsLib.AbsoluteCapNotDecreasing());

        absoluteCap[id] = newCap;
    }

    function increaseRelativeCap(bytes32 id, uint256 newRelativeCap) external timelocked {
        require(newRelativeCap > relativeCap[id], ErrorsLib.RelativeCapNotIncreasing());

        if (relativeCap[id] == 0) idsWithRelativeCap.push(id);
        relativeCap[id] = newRelativeCap;
    }

    function decreaseRelativeCap(bytes32 id, uint256 newRelativeCap, uint256 index) external timelocked {
        require(newRelativeCap < relativeCap[id], ErrorsLib.RelativeCapNotDecreasing());
        require(idsWithRelativeCap[index] == id, ErrorsLib.IdNotFound());
        require(
            allocation[id] <= totalAssets.mulDiv(newRelativeCap, WAD, Math.Rounding.Floor),
            ErrorsLib.RelativeCapExceeded()
        );

        if (newRelativeCap == 0) {
            idsWithRelativeCap[index] = idsWithRelativeCap[idsWithRelativeCap.length - 1];
            idsWithRelativeCap.pop();
        }
        relativeCap[id] = newRelativeCap;
    }

    /* ALLOCATOR ACTIONS */

    // Note how the discrepancy between transferred amount and increase in market.totalAssets() is handled:
    // it is not reflected in vault.totalAssets() but will have an impact on interest.
    function reallocateFromIdle(address adapter, bytes memory data, uint256 amount) external {
        require(isAllocator[msg.sender] || isSentinel[msg.sender], ErrorsLib.NotAllocator());
        require(isAdapter[adapter], ErrorsLib.NotAdapter());

        asset.transfer(adapter, amount);
        bytes32[] memory ids = IAdapter(adapter).allocateIn(data, amount);

        for (uint256 i; i < ids.length; i++) {
            allocation[ids[i]] += amount;

            require(allocation[ids[i]] <= absoluteCap[ids[i]], ErrorsLib.AbsoluteCapExceeded());
            require(
                allocation[ids[i]] <= totalAssets.mulDiv(relativeCap[ids[i]], WAD, Math.Rounding.Floor),
                ErrorsLib.RelativeCapExceeded()
            );
        }
    }

    // Note how the discrepancy between transferred amount and decrease in market.totalAssets() is handled:
    // it is not reflected in vault.totalAssets() but will have an impact on interest.
    function reallocateToIdle(address adapter, bytes memory data, uint256 amount) external {
        require(isAllocator[msg.sender] || isSentinel[msg.sender], ErrorsLib.NotAllocator());
        require(isAdapter[adapter], ErrorsLib.NotAdapter());

        bytes32[] memory ids = IAdapter(adapter).allocateOut(data, amount);

        for (uint256 i; i < ids.length; i++) {
            allocation[ids[i]] = allocation[ids[i]].zeroFloorSub(amount);
        }

        asset.transferFrom(adapter, address(this), amount);
    }

    /* EXCHANGE RATE */

    function accrueInterest() public {
        (uint256 performanceFeeShares, uint256 managementFeeShares, uint256 protocolFeeShares, uint256 newTotalAssets) =
            accruedFeeShares();

        totalAssets = newTotalAssets;

        address protocolFeeRecipient = IVaultV2Factory(factory).protocolFeeRecipient();
        if (performanceFeeShares != 0) _mint(performanceFeeRecipient, performanceFeeShares);
        if (managementFeeShares != 0) _mint(managementFeeRecipient, managementFeeShares);
        if (protocolFeeShares != 0) _mint(protocolFeeRecipient, protocolFeeShares);

        lastUpdate = block.timestamp;
    }

    function accruedFeeShares() public view returns (uint256, uint256, uint256, uint256) {
        uint256 elapsed = block.timestamp - lastUpdate;
        uint256 interest = IIRM(irm).interestPerSecond() * elapsed;
        uint256 newTotalAssets = totalAssets + interest;

        uint256 protocolFee = IVaultV2Factory(factory).protocolFee();

        uint256 performanceFeeShares;
        uint256 managementFeeShares;
        uint256 protocolPerformanceFeeShares;
        uint256 protocolManagementFeeShares;
        // Note that the fee assets is subtracted from the total assets in the fee shares calculation to compensate for
        // the fact that total assets is already increased by the total interest (including the fee assets).
        // Note that `feeAssets` may be rounded down to 0 if `totalInterest * fee < WAD`.
        uint256 totalPerformanceFeeShares;
        if (interest > 0 && performanceFee != 0) {
            uint256 performanceFeeAssets = interest.mulDiv(performanceFee, WAD, Math.Rounding.Floor);
            totalPerformanceFeeShares = performanceFeeAssets.mulDiv(
                totalSupply() + 1, newTotalAssets + 1 - performanceFeeAssets, Math.Rounding.Floor
            );
            protocolPerformanceFeeShares = totalPerformanceFeeShares.mulDiv(protocolFee, WAD, Math.Rounding.Floor);
            performanceFeeShares = totalPerformanceFeeShares - protocolPerformanceFeeShares;
        }
        if (managementFee != 0) {
            // Using newTotalAssets to make all approximations consistent.
            uint256 managementFeeAssets = (newTotalAssets * elapsed).mulDiv(managementFee, WAD, Math.Rounding.Floor);
            uint256 totalManagementFeeShares = managementFeeAssets.mulDiv(
                totalSupply() + 1 + totalPerformanceFeeShares,
                newTotalAssets + 1 - managementFeeAssets,
                Math.Rounding.Floor
            );
            protocolManagementFeeShares = totalManagementFeeShares.mulDiv(protocolFee, WAD, Math.Rounding.Floor);
            managementFeeShares = totalManagementFeeShares - protocolManagementFeeShares;
        }
        uint256 protocolFeeShares = protocolPerformanceFeeShares + protocolManagementFeeShares;
        return (performanceFeeShares, managementFeeShares, protocolFeeShares, newTotalAssets);
    }

    function convertToShares(uint256 assets) external view returns (uint256) {
        return convertToShares(assets, Math.Rounding.Floor);
    }

    // TODO: extract virtual shares and assets (= 1).
    function convertToShares(uint256 assets, Math.Rounding rounding) internal view returns (uint256 shares) {
        shares = assets.mulDiv(totalSupply() + 1, totalAssets + 1, rounding);
    }

    function convertToAssets(uint256 shares) external view returns (uint256) {
        return convertToAssets(shares, Math.Rounding.Floor);
    }

    function convertToAssets(uint256 shares, Math.Rounding rounding) internal view returns (uint256 assets) {
        assets = shares.mulDiv(totalAssets + 1, totalSupply() + 1, rounding);
    }

    /* USER INTERACTION */

    function _deposit(uint256 assets, uint256 shares, address receiver) internal {
        SafeERC20.safeTransferFrom(asset, msg.sender, address(this), assets);
        _mint(receiver, shares);
        totalAssets += assets;
    }

    // TODO: how to hook on deposit so that assets are atomically allocated ?
    function deposit(uint256 assets, address receiver) public virtual returns (uint256 shares) {
        accrueInterest();
        // Note that it could be made more efficient by caching totalAssets.
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
        totalAssets -= assets;

        for (uint256 i; i < idsWithRelativeCap.length; i++) {
            bytes32 id = idsWithRelativeCap[i];
            require(
                allocation[id] <= totalAssets.mulDiv(relativeCap[id], WAD, Math.Rounding.Floor),
                ErrorsLib.RelativeCapExceeded()
            );
        }
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

    /* TIMELOCKS */

    function submit(bytes calldata data) external {
        bytes4 functionSelector = bytes4(data);
        require(isAuthorizedToSubmit(msg.sender, functionSelector), ErrorsLib.Unauthorized());

        require(validAt[data] == 0, ErrorsLib.DataAlreadyPending());

        validAt[data] = block.timestamp + timelockDuration[functionSelector];
    }

    modifier timelocked() {
        require(validAt[msg.data] != 0 && block.timestamp >= validAt[msg.data], ErrorsLib.DataNotTimelocked());
        validAt[msg.data] = 0;
        _;
    }

    /// @dev Authorized to submit can revoke.
    function revoke(bytes calldata data) external {
        require(
            isAuthorizedToSubmit(msg.sender, bytes4(data))
                || (isSentinel[msg.sender] && bytes4(data) != IVaultV2.setIsSentinel.selector),
            ErrorsLib.Unauthorized()
        );
        require(validAt[data] != 0);
        validAt[data] = 0;
    }

    function isAuthorizedToSubmit(address sender, bytes4 functionSelector) internal view returns (bool) {
        // Owner functions
        if (functionSelector == IVaultV2.setPerformanceFeeRecipient.selector) return sender == owner;
        if (functionSelector == IVaultV2.setManagementFeeRecipient.selector) return sender == owner;
        if (functionSelector == IVaultV2.setIsSentinel.selector) return sender == owner;
        if (functionSelector == IVaultV2.setOwner.selector) return sender == owner;
        if (functionSelector == IVaultV2.setCurator.selector) return sender == owner;
        if (functionSelector == IVaultV2.setIRM.selector) return sender == owner;
        if (functionSelector == IVaultV2.setTreasurer.selector) return sender == owner;
        if (functionSelector == IVaultV2.setIsAllocator.selector) return sender == owner;
        if (functionSelector == IVaultV2.setIsAdapter.selector) return sender == owner;
        if (functionSelector == IVaultV2.increaseTimelock.selector) return sender == owner;
        if (functionSelector == IVaultV2.decreaseTimelock.selector) return sender == owner;
        // Treasurer functions
        if (functionSelector == IVaultV2.setPerformanceFee.selector) return sender == treasurer;
        if (functionSelector == IVaultV2.setManagementFee.selector) return sender == treasurer;
        // Curator functions
        if (functionSelector == IVaultV2.increaseAbsoluteCap.selector) return sender == curator;
        if (functionSelector == IVaultV2.decreaseAbsoluteCap.selector) return sender == curator || isSentinel[sender];
        if (functionSelector == IVaultV2.increaseRelativeCap.selector) return sender == curator;
        if (functionSelector == IVaultV2.decreaseRelativeCap.selector) return sender == curator;
        return false;
    }

    /* INTERFACE */

    function maxWithdraw(address) external view returns (uint256) {
        return asset.balanceOf(address(this));
    }
}
