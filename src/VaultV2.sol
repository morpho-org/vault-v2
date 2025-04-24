// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.28;

import {IVaultV2, IERC20, IAdapter} from "./interfaces/IVaultV2.sol";
import {IIRM} from "./interfaces/IIRM.sol";
import {ProtocolFee, IVaultV2Factory} from "./interfaces/IVaultV2Factory.sol";

import {ErrorsLib} from "./libraries/ErrorsLib.sol";
import {EventsLib} from "./libraries/EventsLib.sol";
import "./libraries/ConstantsLib.sol";
import {MathLib} from "./libraries/MathLib.sol";
import {SafeTransferLib} from "./libraries/SafeTransferLib.sol";

contract VaultV2 is IVaultV2 {
    using MathLib for uint256;
    using SafeTransferLib for IERC20;

    /* IMMUTABLE */

    address public immutable factory;
    address public immutable asset;

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

    /// @dev calldata => executable at
    mapping(bytes => uint256) public validAt;
    /// @dev function selector => timelock duration
    mapping(bytes4 => uint256) public timelock;

    uint256 public totalSupply;
    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;
    mapping(address => uint256) public nonces;

    /* CONSTRUCTOR */

    constructor(address _owner, address _asset) {
        factory = msg.sender;
        asset = _asset;
        owner = _owner;
        lastUpdate = block.timestamp;
        timelock[IVaultV2.decreaseTimelock.selector] = TIMELOCK_CAP;
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

        accrueInterest();

        performanceFeeRecipient = newPerformanceFeeRecipient;
    }

    function setManagementFeeRecipient(address newManagementFeeRecipient) external timelocked {
        require(newManagementFeeRecipient != address(0) || managementFee == 0, ErrorsLib.FeeInvariantBroken());

        accrueInterest();

        managementFeeRecipient = newManagementFeeRecipient;
    }

    function setIsAdapter(address adapter, bool newIsAdapter) external timelocked {
        isAdapter[adapter] = newIsAdapter;
    }

    function increaseTimelock(bytes4 selector, uint256 newDuration) external timelocked {
        require(selector != IVaultV2.decreaseTimelock.selector, ErrorsLib.TimelockCapIsFixed());
        require(newDuration <= TIMELOCK_CAP, ErrorsLib.TimelockDurationTooHigh());
        require(newDuration > timelock[selector], ErrorsLib.TimelockNotIncreasing());

        timelock[selector] = newDuration;
    }

    function decreaseTimelock(bytes4 selector, uint256 newDuration) external timelocked {
        require(selector != IVaultV2.decreaseTimelock.selector, ErrorsLib.TimelockCapIsFixed());
        require(newDuration < timelock[selector], ErrorsLib.TimelockNotDecreasing());

        timelock[selector] = newDuration;
    }

    /* TREASURER ACTIONS */

    function setPerformanceFee(uint256 newPerformanceFee) external timelocked {
        require(newPerformanceFee <= MAX_PERFORMANCE_FEE, ErrorsLib.FeeTooHigh());
        require(performanceFeeRecipient != address(0), ErrorsLib.FeeInvariantBroken());

        accrueInterest();

        performanceFee = newPerformanceFee;
    }

    function setManagementFee(uint256 newManagementFee) external timelocked {
        require(newManagementFee <= MAX_MANAGEMENT_FEE, ErrorsLib.FeeTooHigh());
        require(managementFeeRecipient != address(0), ErrorsLib.FeeInvariantBroken());

        accrueInterest();

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
        require(allocation[id] <= totalAssets.mulDivDown(newRelativeCap, WAD), ErrorsLib.RelativeCapExceeded());

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

        SafeTransferLib.safeTransfer(IERC20(asset), adapter, amount);
        bytes32[] memory ids = IAdapter(adapter).allocateIn(data, amount);

        for (uint256 i; i < ids.length; i++) {
            allocation[ids[i]] += amount;

            require(allocation[ids[i]] <= absoluteCap[ids[i]], ErrorsLib.AbsoluteCapExceeded());
            require(
                allocation[ids[i]] <= totalAssets.mulDivDown(relativeCap[ids[i]], WAD), ErrorsLib.RelativeCapExceeded()
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

        SafeTransferLib.safeTransferFrom(IERC20(asset), adapter, address(this), amount);
    }

    /* EXCHANGE RATE */

    function accrueInterest() public {
        (uint256 performanceFeeShares, uint256 managementFeeShares, uint256 protocolFeeShares, uint256 newTotalAssets) =
            accrueInterestView();

        totalAssets = newTotalAssets;

        if (performanceFeeShares != 0) _mint(performanceFeeRecipient, performanceFeeShares);
        if (managementFeeShares != 0) _mint(managementFeeRecipient, managementFeeShares);
        if (protocolFeeShares != 0) _mint(IVaultV2Factory(factory).protocolFeeRecipient(), protocolFeeShares);

        lastUpdate = block.timestamp;
    }

    function accrueInterestView() public view returns (uint256, uint256, uint256, uint256) {
        uint256 elapsed = block.timestamp - lastUpdate;
        if (elapsed == 0) return (0, 0, 0, totalAssets);
        uint256 interestPerSecond = IIRM(irm).interestPerSecond(totalAssets, elapsed);
        require(interestPerSecond <= totalAssets.mulDivDown(MAX_RATE_PER_SECOND, WAD), ErrorsLib.InvalidRate());
        uint256 interest = interestPerSecond * elapsed;
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
            uint256 performanceFeeAssets = interest.mulDivDown(performanceFee, WAD);
            totalPerformanceFeeShares =
                performanceFeeAssets.mulDivDown(totalSupply + 1, newTotalAssets + 1 - performanceFeeAssets);
            protocolPerformanceFeeShares = totalPerformanceFeeShares.mulDivDown(protocolFee, WAD);
            performanceFeeShares = totalPerformanceFeeShares - protocolPerformanceFeeShares;
        }
        if (managementFee != 0) {
            // Using newTotalAssets to make all approximations consistent.
            uint256 managementFeeAssets = (newTotalAssets * elapsed).mulDivDown(managementFee, WAD);
            uint256 totalManagementFeeShares = managementFeeAssets.mulDivDown(
                totalSupply + 1 + totalPerformanceFeeShares, newTotalAssets + 1 - managementFeeAssets
            );
            protocolManagementFeeShares = totalManagementFeeShares.mulDivDown(protocolFee, WAD);
            managementFeeShares = totalManagementFeeShares - protocolManagementFeeShares;
        }
        uint256 protocolFeeShares = protocolPerformanceFeeShares + protocolManagementFeeShares;
        return (performanceFeeShares, managementFeeShares, protocolFeeShares, newTotalAssets);
    }

    function previewDeposit(uint256 assets) public view returns (uint256) {
        (uint256 performanceFeeShares, uint256 managementFeeShares, uint256 protocolFeeShares, uint256 newTotalAssets) =
            accrueInterestView();
        uint256 newTotalSupply = totalSupply + performanceFeeShares + managementFeeShares + protocolFeeShares;
        return assets.mulDivDown(newTotalSupply + 1, newTotalAssets + 1);
    }

    function previewWithdraw(uint256 assets) public view returns (uint256) {
        (uint256 performanceFeeShares, uint256 managementFeeShares, uint256 protocolFeeShares, uint256 newTotalAssets) =
            accrueInterestView();
        uint256 newTotalSupply = totalSupply + performanceFeeShares + managementFeeShares + protocolFeeShares;
        return assets.mulDivUp(newTotalSupply + 1, newTotalAssets + 1);
    }

    function previewMint(uint256 shares) public view returns (uint256) {
        (uint256 performanceFeeShares, uint256 managementFeeShares, uint256 protocolFeeShares, uint256 newTotalAssets) =
            accrueInterestView();
        uint256 newTotalSupply = totalSupply + performanceFeeShares + managementFeeShares + protocolFeeShares;
        return shares.mulDivDown(newTotalSupply + 1, newTotalAssets + 1);
    }

    function previewRedeem(uint256 shares) public view returns (uint256) {
        (uint256 performanceFeeShares, uint256 managementFeeShares, uint256 protocolFeeShares, uint256 newTotalAssets) =
            accrueInterestView();
        uint256 newTotalSupply = totalSupply + performanceFeeShares + managementFeeShares + protocolFeeShares;
        return shares.mulDivUp(newTotalSupply + 1, newTotalAssets + 1);
    }

    /* USER INTERACTION */

    function _deposit(uint256 assets, uint256 shares, address receiver) internal {
        SafeTransferLib.safeTransferFrom(IERC20(asset), msg.sender, address(this), assets);
        _mint(receiver, shares);
        totalAssets += assets;
    }

    // TODO: how to hook on deposit so that assets are atomically allocated ?
    function deposit(uint256 assets, address receiver) public returns (uint256) {
        accrueInterest();
        uint256 shares = previewDeposit(assets);
        _deposit(assets, shares, receiver);
        return shares;
    }

    function mint(uint256 shares, address receiver) public returns (uint256) {
        accrueInterest();
        uint256 assets = previewMint(shares);
        _deposit(assets, shares, receiver);
        return assets;
    }

    function _withdraw(uint256 assets, uint256 shares, address receiver, address supplier) internal {
        uint256 _allowance = allowance[supplier][msg.sender];
        if (msg.sender != supplier && _allowance != type(uint256).max) {
            allowance[supplier][msg.sender] = _allowance - shares;
        }
        _burn(supplier, shares);
        totalAssets -= assets;

        for (uint256 i; i < idsWithRelativeCap.length; i++) {
            bytes32 id = idsWithRelativeCap[i];
            require(allocation[id] <= totalAssets.mulDivDown(relativeCap[id], WAD), ErrorsLib.RelativeCapExceeded());
        }

        SafeTransferLib.safeTransfer(IERC20(asset), receiver, assets);
    }

    // Note that it is not callable by default, if there is no liquidity.
    // This is actually a feature, so that the curator can pause withdrawals if necessary/wanted.
    function withdraw(uint256 assets, address receiver, address supplier) public returns (uint256) {
        accrueInterest();
        uint256 shares = previewWithdraw(assets);
        _withdraw(assets, shares, receiver, supplier);
        return shares;
    }

    function redeem(uint256 shares, address receiver, address supplier) public returns (uint256) {
        accrueInterest();
        uint256 assets = previewRedeem(shares);
        _withdraw(assets, shares, receiver, supplier);
        return assets;
    }

    /* TIMELOCKS */

    function submit(bytes calldata data) external {
        bytes4 selector = bytes4(data);
        require(isAuthorizedToSubmit(msg.sender, selector), ErrorsLib.Unauthorized());

        require(validAt[data] == 0, ErrorsLib.DataAlreadyPending());

        validAt[data] = block.timestamp + timelock[selector];
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

    function isAuthorizedToSubmit(address sender, bytes4 selector) internal view returns (bool) {
        // Owner functions
        if (selector == IVaultV2.setPerformanceFeeRecipient.selector) return sender == owner;
        if (selector == IVaultV2.setManagementFeeRecipient.selector) return sender == owner;
        if (selector == IVaultV2.setIsSentinel.selector) return sender == owner;
        if (selector == IVaultV2.setOwner.selector) return sender == owner;
        if (selector == IVaultV2.setCurator.selector) return sender == owner;
        if (selector == IVaultV2.setIRM.selector) return sender == owner;
        if (selector == IVaultV2.setTreasurer.selector) return sender == owner;
        if (selector == IVaultV2.setIsAllocator.selector) return sender == owner;
        if (selector == IVaultV2.setIsAdapter.selector) return sender == owner;
        if (selector == IVaultV2.increaseTimelock.selector) return sender == owner;
        if (selector == IVaultV2.decreaseTimelock.selector) return sender == owner;
        // Treasurer functions
        if (selector == IVaultV2.setPerformanceFee.selector) return sender == treasurer;
        if (selector == IVaultV2.setManagementFee.selector) return sender == treasurer;
        // Curator functions
        if (selector == IVaultV2.increaseAbsoluteCap.selector) return sender == curator;
        if (selector == IVaultV2.decreaseAbsoluteCap.selector) return sender == curator || isSentinel[sender];
        if (selector == IVaultV2.increaseRelativeCap.selector) return sender == curator;
        if (selector == IVaultV2.decreaseRelativeCap.selector) return sender == curator;
        return false;
    }

    /* INTERFACE */

    function transfer(address to, uint256 amount) public returns (bool) {
        require(to != address(0), ErrorsLib.ZeroAddress());
        balanceOf[msg.sender] -= amount;
        balanceOf[to] += amount;
        emit EventsLib.Transfer(msg.sender, to, amount);
        return true;
    }

    function transferFrom(address from, address to, uint256 amount) public returns (bool) {
        require(from != address(0), ErrorsLib.ZeroAddress());
        require(to != address(0), ErrorsLib.ZeroAddress());
        uint256 _allowance = allowance[from][msg.sender];

        if (_allowance < type(uint256).max) allowance[from][msg.sender] = _allowance - amount;

        balanceOf[from] -= amount;
        balanceOf[to] += amount;
        emit EventsLib.Transfer(from, to, amount);

        return true;
    }

    function approve(address spender, uint256 amount) public returns (bool) {
        allowance[msg.sender][spender] = amount;
        emit EventsLib.Approval(msg.sender, spender, amount);
        return true;
    }

    function permit(address _owner, address spender, uint256 value, uint256 deadline, uint8 v, bytes32 r, bytes32 s)
        public
    {
        bytes32 hashStruct = keccak256(abi.encode(PERMIT_TYPEHASH, _owner, spender, value, nonces[_owner]++, deadline));
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", DOMAIN_SEPARATOR(), hashStruct));
        address recoveredAddress = ecrecover(digest, v, r, s);

        require(deadline >= block.timestamp, ErrorsLib.PermitDeadlineExpired());
        require(recoveredAddress != address(0) && recoveredAddress == _owner, ErrorsLib.InvalidSigner());

        allowance[recoveredAddress][spender] = value;
        emit EventsLib.Approval(recoveredAddress, spender, value);
    }

    function DOMAIN_SEPARATOR() public view returns (bytes32) {
        return keccak256(abi.encode(DOMAIN_TYPEHASH, block.chainid, address(this)));
    }

    /* ERC20 INTERNAL */

    function _mint(address to, uint256 amount) internal {
        require(to != address(0), ErrorsLib.ZeroAddress());
        balanceOf[to] += amount;
        totalSupply += amount;
        emit EventsLib.Transfer(address(0), to, amount);
    }

    function _burn(address from, uint256 amount) internal {
        require(from != address(0), ErrorsLib.ZeroAddress());
        balanceOf[from] -= amount;
        totalSupply -= amount;
        emit EventsLib.Transfer(from, address(0), amount);
    }
}
