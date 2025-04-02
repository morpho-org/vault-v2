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

contract VaultV2 is ERC20, IVaultV2 {
    using Math for uint256;

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
    address public guardian;
    address public treasurer;
    mapping(address => bool) public isSentinel;
    mapping(address => bool) public isAllocator;

    uint256 public performanceFee;
    address public performanceFeeRecipient;
    uint256 public managementFee;
    address public managementFeeRecipient;
    uint256 public exitPremium;

    address public irm;
    uint256 public lastUpdate;
    uint256 public totalAssets;

    // Adapter is trusted to pass the expected ids when supplying assets.
    mapping(address => bool) public isAdapter;

    // Key is an abstract id.
    // It can represent a protocol, a collateral, a duration etc.
    // Maybe it could be bigger to contain more data.
    mapping(bytes32 => uint256) public absoluteCap; // todo how to handle interest ?
    mapping(bytes32 => uint256) public relativeCap;
    bytes32[] public idsWithRelativeCap; // useful to iterate over all ids with relative cap in withdrawals.
    mapping(bytes32 => uint256) public allocation; // by design double counting some stuff.

    address public depositAdapter;
    bytes public depositData;
    address public withdrawAdapter;
    bytes public withdrawData;

    mapping(bytes => uint256) public validAt;
    mapping(bytes4 => uint64) public timelockDuration;

    mapping(address => mapping(address => bool)) public canRequestExit;
    mapping(address => uint256) public exitBalances;
    uint256 public totalExitSupply;

    /* CONSTRUCTOR */

    constructor(
        address _factory,
        address _owner,
        address _curator,
        address _asset,
        string memory _name,
        string memory _symbol
    ) ERC20(_name, _symbol) {
        factory = _factory;
        asset = IERC20(_asset);
        owner = _owner;
        curator = _curator;
        lastUpdate = block.timestamp;
        timelockDuration[IVaultV2.decreaseTimelock.selector] = TIMELOCK_CAP;
        // The vault starts with no IRM, no markets and no assets. To be configured afterwards.
    }

    /* OWNER ACTIONS */

    function setPerformanceFeeRecipient(address newPerformanceFeeRecipient) external timelocked {
        performanceFeeRecipient = newPerformanceFeeRecipient;
    }

    function setManagementFeeRecipient(address newManagementFeeRecipient) external timelocked {
        managementFeeRecipient = newManagementFeeRecipient;
    }

    function setOwner(address newOwner) external timelocked {
        owner = newOwner;
    }

    function setCurator(address newCurator) external timelocked {
        curator = newCurator;
    }

    function setIsSentinel(address newSentinel, bool newIsSentinel) external timelocked {
        isSentinel[newSentinel] = newIsSentinel;
    }

    function setGuardian(address newGuardian) external timelocked {
        guardian = newGuardian;
    }

    function setTreasurer(address newTreasurer) external timelocked {
        treasurer = newTreasurer;
    }

    function increaseTimelock(bytes4 functionSelector, uint64 newDuration) external timelocked {
        require(functionSelector != IVaultV2.decreaseTimelock.selector, ErrorsLib.TimelockCapIsFixed());
        require(newDuration <= TIMELOCK_CAP, ErrorsLib.TimelockDurationTooHigh());
        require(newDuration > timelockDuration[functionSelector], "timelock not increasing");

        timelockDuration[functionSelector] = newDuration;
    }

    function decreaseTimelock(bytes4 functionSelector, uint64 newDuration) external timelocked {
        require(functionSelector != IVaultV2.decreaseTimelock.selector, ErrorsLib.TimelockCapIsFixed());
        require(newDuration <= TIMELOCK_CAP, ErrorsLib.TimelockDurationTooHigh());
        require(newDuration < timelockDuration[functionSelector], "timelock not decreasing");

        timelockDuration[functionSelector] = newDuration;
    }

    function addAdapter(address adapter) external timelocked {
        isAdapter[adapter] = true;
    }

    function removeAdapter(address adapter) external timelocked {
        isAdapter[adapter] = false;
    }

    function setIsAllocator(address allocator, bool newIsAllocator) external timelocked {
        isAllocator[allocator] = newIsAllocator;
    }

    /* TREASURER ACTIONS */

    function setPerformanceFee(uint256 newPerformanceFee) external timelocked {
        require(newPerformanceFee < WAD, ErrorsLib.FeeTooHigh());

        performanceFee = newPerformanceFee;
    }

    function setManagementFee(uint256 newManagementFee) external timelocked {
        require(newManagementFee < WAD, ErrorsLib.FeeTooHigh());

        managementFee = newManagementFee;
    }

    function setExitPremium(uint256 newExitPremium) external timelocked {
        require(newExitPremium < WAD, ErrorsLib.ExitPremiumTooHigh());

        exitPremium = newExitPremium;
    }

    /* CURATOR ACTIONS */

    function setIRM(address newIRM) external timelocked {
        irm = newIRM;
    }

    function increaseAbsoluteCap(bytes32 id, uint256 newCap) external timelocked {
        require(newCap > absoluteCap[id], "absolute cap not increasing");

        absoluteCap[id] = newCap;
    }

    function decreaseAbsoluteCap(bytes32 id, uint256 newCap) external timelocked {
        require(newCap < absoluteCap[id], "absolute cap not decreasing");

        absoluteCap[id] = newCap;
    }

    function increaseRelativeCap(bytes32 id, uint256 newRelativeCap) external timelocked {
        require(newRelativeCap > relativeCap[id], "relative cap not increasing");

        if (relativeCap[id] == 0) idsWithRelativeCap.push(id);
        relativeCap[id] = newRelativeCap;
    }

    function decreaseRelativeCap(bytes32 id, uint256 newRelativeCap, uint256 index) external timelocked {
        require(newRelativeCap < relativeCap[id], "relative cap not decreasing");
        require(idsWithRelativeCap[index] == id, "id not found");

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
        require(isAllocator[msg.sender] || msg.sender == address(this), "not an allocator");
        require(isAdapter[adapter], "not an adapter");

        uint256 totalExitAssets = convertToAssets(totalExitSupply, Math.Rounding.Floor);
        require(totalExitAssets <= asset.balanceOf(address(this)) - amount, "not enough exit assets to withdraw");

        asset.transfer(adapter, amount);
        bytes32[] memory ids = IAdapter(adapter).allocateIn(data, amount);

        for (uint256 i; i < ids.length; i++) {
            allocation[ids[i]] += amount;

            require(allocation[ids[i]] <= absoluteCap[ids[i]], "absolute cap exceeded");
            require(
                allocation[ids[i]] <= totalAssets.mulDiv(relativeCap[ids[i]], WAD, Math.Rounding.Floor),
                "relative cap exceeded"
            );
        }
    }

    // Do not try to redeem normally first
    function requestExit(uint256 shares, address supplier) external {
        if (msg.sender != supplier) require(canRequestExit[supplier][msg.sender], "not allowed to exit");
        _burn(supplier, shares);
        uint256 exitShares = shares * (WAD - exitPremium) / WAD;
        exitBalances[supplier] += exitShares;
        totalExitSupply += exitShares;
    }

    function claimExit(uint256 shares, address receiver, address supplier) external {
        if (msg.sender != supplier) _spendAllowance(supplier, msg.sender, shares);
        exitBalances[supplier] -= shares;
        totalExitSupply -= shares;
        uint256 claimedAmount = convertToAssets(shares, Math.Rounding.Floor);
        asset.transfer(receiver, claimedAmount);
    }

    function approveExit(address spender, bool allowed) external {
        canRequestExit[msg.sender][spender] = allowed;
    }

    // Note how the discrepancy between transferred amount and decrease in market.totalAssets() is handled:
    // it is not reflected in vault.totalAssets() but will have an impact on interest.
    function reallocateToIdle(address adapter, bytes memory data, uint256 amount) external {
        require(isAllocator[msg.sender] || msg.sender == address(this), "not an allocator");
        require(isAdapter[adapter], "not an adapter");

        asset.transferFrom(adapter, address(this), amount);
        bytes32[] memory ids = IAdapter(adapter).allocateOut(data, amount);

        for (uint256 i; i < ids.length; i++) {
            allocation[ids[i]] -= amount;
        }
    }

    function setDepositData(address newDepositAdapter, bytes memory newDepositData) external timelocked {
        depositAdapter = newDepositAdapter;
        depositData = newDepositData;
    }

    function setWithdrawData(address newWithdrawAdapter, bytes memory newWithdrawData) external timelocked {
        withdrawAdapter = newWithdrawAdapter;
        withdrawData = newWithdrawData;
    }

    /* EXCHANGE RATE */

    function accrueInterest() public {
        (
            uint256 ownerPerformanceFeeShares,
            uint256 ownerManagementFeeShares,
            uint256 protocolFeeShares,
            uint256 newTotalAssets
        ) = accruedFeeShares();

        totalAssets = newTotalAssets;

        address protocolFeeRecipient = IVaultV2Factory(factory).protocolFeeRecipient();
        if (ownerPerformanceFeeShares != 0) _mint(performanceFeeRecipient, ownerPerformanceFeeShares);
        if (ownerManagementFeeShares != 0) _mint(managementFeeRecipient, ownerManagementFeeShares);
        if (protocolFeeShares != 0) _mint(protocolFeeRecipient, protocolFeeShares);

        lastUpdate = block.timestamp;
    }

    function accruedFeeShares()
        public
        view
        returns (
            uint256 ownerPerformanceFeeShares,
            uint256 ownerManagementFeeShares,
            uint256 protocolFeeShares,
            uint256 newTotalAssets
        )
    {
        uint256 elapsed = block.timestamp - lastUpdate;
        uint256 interest = IIRM(irm).interestPerSecond() * elapsed;
        newTotalAssets += interest;

        uint256 protocolFee = IVaultV2Factory(factory).protocolFee();

        // Note that the fee assets is subtracted from the total assets in the fee shares calculation to compensate for
        // the fact that total assets is already increased by the total interest (including the fee assets).
        // Note that `feeAssets` may be rounded down to 0 if `totalInterest * fee < WAD`.
        if (interest > 0 && performanceFee != 0) {
            uint256 performanceFeeAssets = interest.mulDiv(performanceFee, WAD, Math.Rounding.Floor);
            uint256 totalProtocolPerformanceFeeShares = performanceFeeAssets.mulDiv(
                totalSupply() + 1, newTotalAssets + 1 - performanceFeeAssets, Math.Rounding.Floor
            );
            uint256 protocolPerformanceFeeShares =
                totalProtocolPerformanceFeeShares.mulDiv(protocolFee, WAD, Math.Rounding.Floor);
            ownerPerformanceFeeShares = totalProtocolPerformanceFeeShares - protocolPerformanceFeeShares;
            protocolFeeShares += protocolPerformanceFeeShares;
        }
        if (managementFee != 0) {
            // Using newTotalAssets to make all approximations consistent.
            uint256 managementFeeAssets = (newTotalAssets * elapsed).mulDiv(managementFee, WAD, Math.Rounding.Floor);
            uint256 totalProtocolManagementFeeShares = managementFeeAssets.mulDiv(
                totalSupply() + 1, newTotalAssets + 1 - managementFeeAssets, Math.Rounding.Floor
            );
            uint256 protocolManagementFeeShares =
                totalProtocolManagementFeeShares.mulDiv(protocolFee, WAD, Math.Rounding.Floor);
            ownerManagementFeeShares = totalProtocolManagementFeeShares - protocolManagementFeeShares;
            protocolFeeShares += protocolManagementFeeShares;
        }
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

        try this.reallocateFromIdle(depositAdapter, depositData, assets) {} catch {}
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
        assets = convertToShares(shares, Math.Rounding.Ceil);
        _deposit(assets, shares, receiver);
    }

    function _withdraw(uint256 assets, uint256 shares, address receiver, address supplier) internal virtual {
        try this.reallocateToIdle(withdrawAdapter, withdrawData, assets) {} catch {}

        if (msg.sender != supplier) _spendAllowance(supplier, msg.sender, shares);
        _burn(supplier, shares);

        uint256 totalExitAssets = convertToAssets(totalExitSupply, Math.Rounding.Floor);
        require(totalExitAssets <= asset.balanceOf(address(this)) - assets, "not enough exit assets to withdraw");
        SafeERC20.safeTransfer(asset, receiver, assets);
        totalAssets -= assets;

        for (uint256 i; i < idsWithRelativeCap.length; i++) {
            bytes32 id = idsWithRelativeCap[i];
            require(
                allocation[id] <= totalAssets.mulDiv(relativeCap[id], WAD, Math.Rounding.Floor), "relative cap exceeded"
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
        assets = convertToShares(shares, Math.Rounding.Floor);
        _withdraw(assets, shares, receiver, supplier);
    }

    /* TIMELOCKS */

    function submit(bytes calldata data) external {
        bytes4 functionSelector = bytes4(data);
        require(isAuthorizedToSubmit(msg.sender, functionSelector), ErrorsLib.Unauthorized());

        require(validAt[data] == 0, "data already pending");

        validAt[data] = block.timestamp + timelockDuration[functionSelector];
    }

    modifier timelocked() {
        require(validAt[msg.data] != 0 && block.timestamp >= validAt[msg.data], "data not timelocked");
        validAt[msg.data] = 0;
        _;
    }

    /// @dev Guardian can revoke everything.
    /// @dev Sentinels can revoke everything except setIsSentinel timelocks.
    /// @dev Authorized to submit can revoke.
    function revoke(bytes calldata data) external {
        require(
            msg.sender == guardian || (isSentinel[msg.sender] && bytes4(data) != IVaultV2.setIsSentinel.selector)
                || isAuthorizedToSubmit(msg.sender, bytes4(data)),
            "unauthorized"
        );
        require(validAt[data] != 0);
        validAt[data] = 0;
    }

    function isAuthorizedToSubmit(address sender, bytes4 functionSelector) internal view returns (bool) {
        // forgefmt: disable-start
        // Owner actions.
        if (functionSelector == IVaultV2.setPerformanceFeeRecipient.selector)   return sender == owner;
        if (functionSelector == IVaultV2.setManagementFeeRecipient.selector)    return sender == owner;
        if (functionSelector == IVaultV2.setIsSentinel.selector)                return sender == owner;
        if (functionSelector == IVaultV2.setOwner.selector)                     return sender == owner;
        if (functionSelector == IVaultV2.setCurator.selector)                   return sender == owner;
        if (functionSelector == IVaultV2.setGuardian.selector)                  return sender == owner;
        if (functionSelector == IVaultV2.setTreasurer.selector)                 return sender == owner;
        if (functionSelector == IVaultV2.setIsAllocator.selector)               return sender == owner || isSentinel[sender];
        // Treasurer actions.
        if (functionSelector == IVaultV2.setPerformanceFee.selector)            return sender == treasurer;
        if (functionSelector == IVaultV2.setManagementFee.selector)             return sender == treasurer;
        if (functionSelector == IVaultV2.setExitPremium.selector)               return sender == treasurer;
        // Curator actions.
        if (functionSelector == IVaultV2.setIRM.selector)                       return sender == curator;
        if (functionSelector == IVaultV2.increaseAbsoluteCap.selector)          return sender == curator;
        if (functionSelector == IVaultV2.decreaseAbsoluteCap.selector)          return sender == curator || isSentinel[sender];
        if (functionSelector == IVaultV2.increaseRelativeCap.selector)          return sender == curator;
        if (functionSelector == IVaultV2.decreaseRelativeCap.selector)          return sender == curator || isSentinel[sender];
        // Allocator actions.
        if (functionSelector == IVaultV2.setDepositData.selector)               return isAllocator[sender];
        if (functionSelector == IVaultV2.setWithdrawData.selector)              return isAllocator[sender];
        // forgefmt: disable-end
        return false;
    }

    /* INTERFACE */

    function balanceOf(address user) public view override(ERC20) returns (uint256) {
        return super.balanceOf(user);
    }

    function maxWithdraw(address) external view returns (uint256) {
        return asset.balanceOf(address(this));
    }
}
