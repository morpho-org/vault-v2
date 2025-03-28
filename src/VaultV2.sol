// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.28;

import {ERC20, IERC20} from "../lib/openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";
import {Math} from "../lib/openzeppelin-contracts/contracts/utils/math/Math.sol";
import {SafeERC20} from "../lib/openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";

import {IMarket, IVaultV2} from "./interfaces/IVaultV2.sol";
import {IIRM} from "./interfaces/IIRM.sol";
import {IAllocator} from "./interfaces/IAllocator.sol";
import {ProtocolFee, IVaultV2Factory} from "./interfaces/IVaultV2Factory.sol";

import {ErrorsLib} from "./libraries/ErrorsLib.sol";
import {ConstantsLib} from "./libraries/ConstantsLib.sol";

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

    // Note that each role could be a smart contract: the owner, curator and allocator.
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

    address public irm;
    uint256 public lastUpdate;
    uint256 public totalAssets;

    IMarket[] public markets;
    mapping(address => uint256) public cap;

    mapping(bytes => uint256) public validAt;
    mapping(bytes4 => uint64) public timelockDuration;

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

    /* AUTHORIZED MULTICALL */

    function multicall(address allocator, bytes[] calldata bundle) external {
        require(isAllocator[allocator], ErrorsLib.Unauthorized());
        IAllocator(allocator).authorizeMulticall(msg.sender, bundle);

        // The allocator is responsible for making sure that bundles cannot reenter.
        unlocked = true;

        for (uint256 i = 0; i < bundle.length; i++) {
            // Note: no need to check that address(this) has code.
            (bool success,) = address(this).delegatecall(bundle[i]);
            require(success, ErrorsLib.FailedDelegateCall());
        }

        unlocked = false;
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
        require(newDuration >= TIMELOCK_CAP, ErrorsLib.TimelockDurationTooHigh());
        require(newDuration < timelockDuration[functionSelector], "timelock not decreasing");

        timelockDuration[functionSelector] = newDuration;
    }

    function setAllocator(address allocator) external timelocked {
        isAllocator[allocator] = true;
    }

    function unsetAllocator(address allocator) external timelocked {
        isAllocator[allocator] = false;
    }

    /* TREASURER ACTIONS */

    function setPerformanceFee(uint256 newPerformanceFee) external timelocked {
        require(newPerformanceFee < ConstantsLib.WAD, ErrorsLib.FeeTooHigh());

        performanceFee = newPerformanceFee;
    }

    function setManagementFee(uint256 newManagementFee) external timelocked {
        require(newManagementFee < ConstantsLib.WAD, ErrorsLib.FeeTooHigh());

        managementFee = newManagementFee;
    }

    /* CURATOR ACTIONS */

    function newMarket(address market) external timelocked {
        asset.approve(market, type(uint256).max);
        markets.push(IMarket(market));
    }

    function dropMarket(uint8 index, address market) external timelocked {
        require(market == address(markets[index]), "inconsistent input");
        asset.approve(market, 0);
        markets[index] = markets[markets.length - 1];
        markets.pop();
    }

    function setIRM(address newIRM) external timelocked {
        irm = newIRM;
    }

    function increaseCap(address market, uint256 newCap) external timelocked {
        require(newCap > cap[market], "cap not increasing");

        cap[market] = newCap;
    }

    function decreaseCap(address market, uint256 newCap) external timelocked {
        require(newCap < cap[market], "cap not decreasing");

        cap[market] = newCap;
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
        newTotalAssets = totalAssets + interest;

        uint256 protocolFee = IVaultV2Factory(factory).protocolFee();

        // Note that the fee assets is subtracted from the total assets in the fee shares calculation to compensate for
        // the fact that total assets is already increased by the total interest (including the fee assets).
        // Note that `feeAssets` may be rounded down to 0 if `totalInterest * fee < WAD`.
        if (interest > 0 && performanceFee != 0) {
            uint256 performanceFeeAssets = interest.mulDiv(performanceFee, ConstantsLib.WAD, Math.Rounding.Floor);
            uint256 totalPerformanceFeeShares = performanceFeeAssets.mulDiv(
                totalSupply() + 1, newTotalAssets + 1 - performanceFeeAssets, Math.Rounding.Floor
            );
            uint256 protocolPerformanceFeeShares =
                totalPerformanceFeeShares.mulDiv(protocolFee, ConstantsLib.WAD, Math.Rounding.Floor);
            ownerPerformanceFeeShares = totalPerformanceFeeShares - protocolPerformanceFeeShares;
            protocolFeeShares += protocolPerformanceFeeShares;
        }
        if (managementFee != 0) {
            // Using newTotalAssets to make all approximations consistent.
            uint256 managementFeeAssets =
                (newTotalAssets * elapsed).mulDiv(managementFee, ConstantsLib.WAD, Math.Rounding.Floor);
            uint256 totalManagementFeeShares = managementFeeAssets.mulDiv(
                totalSupply() + 1, newTotalAssets + 1 - managementFeeAssets, Math.Rounding.Floor
            );
            uint256 protocolManagementFeeShares =
                totalManagementFeeShares.mulDiv(protocolFee, ConstantsLib.WAD, Math.Rounding.Floor);
            ownerManagementFeeShares = totalManagementFeeShares - protocolManagementFeeShares;
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
        if (msg.sender != supplier) _spendAllowance(supplier, msg.sender, shares);
        _burn(supplier, shares);
        SafeERC20.safeTransfer(asset, receiver, assets);
        totalAssets -= assets;
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
        // Owner actions.
        if (functionSelector == IVaultV2.setPerformanceFeeRecipient.selector) return sender == owner;
        else if (functionSelector == IVaultV2.setManagementFeeRecipient.selector) return sender == owner;
        else if (functionSelector == IVaultV2.setIsSentinel.selector) return sender == owner;
        else if (functionSelector == IVaultV2.setOwner.selector) return sender == owner;
        else if (functionSelector == IVaultV2.setCurator.selector) return sender == owner;
        else if (functionSelector == IVaultV2.setGuardian.selector) return sender == owner;
        else if (functionSelector == IVaultV2.setTreasurer.selector) return sender == owner;
        else if (functionSelector == IVaultV2.setAllocator.selector) return sender == owner;
        else if (functionSelector == IVaultV2.unsetAllocator.selector) return sender == owner || isSentinel[sender];
        // Treasurer actions.
        else if (functionSelector == IVaultV2.setPerformanceFee.selector) return sender == treasurer;
        else if (functionSelector == IVaultV2.setManagementFee.selector) return sender == treasurer;
        // Curator actions.
        else if (functionSelector == IVaultV2.setIRM.selector) return sender == curator;
        else if (functionSelector == IVaultV2.increaseCap.selector) return sender == curator;
        else if (functionSelector == IVaultV2.decreaseCap.selector) return sender == curator || isSentinel[sender];
        else if (functionSelector == IVaultV2.newMarket.selector) return sender == curator;
        else if (functionSelector == IVaultV2.dropMarket.selector) return sender == curator;
        else return false;
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
