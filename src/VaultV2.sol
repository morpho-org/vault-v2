// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.28;

import {IVaultV2, IERC20, IAdapter} from "./interfaces/IVaultV2.sol";
import {IIRM} from "./interfaces/IIRM.sol";

import {ErrorsLib} from "./libraries/ErrorsLib.sol";
import {EventsLib} from "./libraries/EventsLib.sol";
import "./libraries/ConstantsLib.sol";
import {MathLib} from "./libraries/MathLib.sol";
import {SafeERC20Lib} from "./libraries/SafeERC20Lib.sol";
import {IGate} from "./interfaces/IGate.sol";

contract VaultV2 is IVaultV2 {
    using MathLib for uint256;

    /* IMMUTABLE */

    address public immutable asset;

    /* STORAGE */

    address public owner;
    address public curator;
    address public treasurer;
    address public irm;
    address public gate;
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

    address public liquidityAdapter;
    bytes public liquidityData;

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

    function setGate(address newGate) external timelocked {
        gate = newGate;
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
        require(adapter != liquidityAdapter, ErrorsLib.LiquidityAdapterInvariantBroken());
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

    function reallocateFromIdle(address adapter, bytes memory data, uint256 amount) external {
        require(
            isAllocator[msg.sender] || isSentinel[msg.sender] || msg.sender == address(this), ErrorsLib.NotAllocator()
        );
        require(isAdapter[adapter], ErrorsLib.NotAdapter());

        SafeERC20Lib.safeTransfer(asset, adapter, amount);
        bytes32[] memory ids = IAdapter(adapter).allocateIn(data, amount);

        for (uint256 i; i < ids.length; i++) {
            allocation[ids[i]] += amount;

            require(allocation[ids[i]] <= absoluteCap[ids[i]], ErrorsLib.AbsoluteCapExceeded());
            require(
                allocation[ids[i]] <= totalAssets.mulDivDown(relativeCap[ids[i]], WAD), ErrorsLib.RelativeCapExceeded()
            );
        }
    }

    function reallocateToIdle(address adapter, bytes memory data, uint256 amount) external {
        require(
            isAllocator[msg.sender] || isSentinel[msg.sender] || msg.sender == address(this), ErrorsLib.NotAllocator()
        );
        require(isAdapter[adapter], ErrorsLib.NotAdapter());

        bytes32[] memory ids = IAdapter(adapter).allocateOut(data, amount);

        for (uint256 i; i < ids.length; i++) {
            allocation[ids[i]] = allocation[ids[i]].zeroFloorSub(amount);
        }

        SafeERC20Lib.safeTransferFrom(asset, adapter, address(this), amount);
    }

    function setLiquidityAdapter(address newLiquidityAdapter) external {
        require(isAllocator[msg.sender], ErrorsLib.NotAllocator());
        require(
            newLiquidityAdapter == address(0) || isAdapter[newLiquidityAdapter],
            ErrorsLib.LiquidityAdapterInvariantBroken()
        );
        liquidityAdapter = newLiquidityAdapter;
    }

    function setLiquidityData(bytes memory newLiquidityData) external {
        require(isAllocator[msg.sender], ErrorsLib.NotAllocator());
        liquidityData = newLiquidityData;
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

    /* EXCHANGE RATE */

    function accrueInterest() public {
        (uint256 performanceFeeShares, uint256 managementFeeShares, uint256 newTotalAssets) = accrueInterestView();

        totalAssets = newTotalAssets;

        if (performanceFeeShares != 0) createShares(performanceFeeRecipient, performanceFeeShares);
        if (managementFeeShares != 0) createShares(managementFeeRecipient, managementFeeShares);

        lastUpdate = block.timestamp;
    }

    function accrueInterestView() public view returns (uint256, uint256, uint256) {
        uint256 elapsed = block.timestamp - lastUpdate;
        if (elapsed == 0) return (0, 0, totalAssets);
        uint256 interestPerSecond = IIRM(irm).interestPerSecond(totalAssets, elapsed);
        require(interestPerSecond <= totalAssets.mulDivDown(MAX_RATE_PER_SECOND, WAD), ErrorsLib.InvalidRate());
        uint256 interest = interestPerSecond * elapsed;
        uint256 newTotalAssets = totalAssets + interest;

        uint256 performanceFeeShares;
        uint256 managementFeeShares;
        // Note that the fee assets is subtracted from the total assets in the fee shares calculation to compensate for
        // the fact that total assets is already increased by the total interest (including the fee assets).
        // Note that `feeAssets` may be rounded down to 0 if `totalInterest * fee < WAD`.
        if (interest > 0 && performanceFee != 0) {
            uint256 performanceFeeAssets = interest.mulDivDown(performanceFee, WAD);
            performanceFeeShares =
                performanceFeeAssets.mulDivDown(totalSupply + 1, newTotalAssets + 1 - performanceFeeAssets);
        }
        if (managementFee != 0) {
            // Using newTotalAssets to make all approximations consistent.
            uint256 managementFeeAssets = (newTotalAssets * elapsed).mulDivDown(managementFee, WAD);
            managementFeeShares = managementFeeAssets.mulDivDown(
                totalSupply + 1 + performanceFeeShares, newTotalAssets + 1 - managementFeeAssets
            );
        }
        return (performanceFeeShares, managementFeeShares, newTotalAssets);
    }

    function previewDeposit(uint256 assets) public view returns (uint256) {
        (uint256 performanceFeeShares, uint256 managementFeeShares, uint256 newTotalAssets) = accrueInterestView();
        uint256 newTotalSupply = totalSupply + performanceFeeShares + managementFeeShares;
        return assets.mulDivDown(newTotalSupply + 1, newTotalAssets + 1);
    }

    function previewWithdraw(uint256 assets) public view returns (uint256) {
        (uint256 performanceFeeShares, uint256 managementFeeShares, uint256 newTotalAssets) = accrueInterestView();
        uint256 newTotalSupply = totalSupply + performanceFeeShares + managementFeeShares;
        return assets.mulDivUp(newTotalSupply + 1, newTotalAssets + 1);
    }

    function previewMint(uint256 shares) public view returns (uint256) {
        (uint256 performanceFeeShares, uint256 managementFeeShares, uint256 newTotalAssets) = accrueInterestView();
        uint256 newTotalSupply = totalSupply + performanceFeeShares + managementFeeShares;
        return shares.mulDivDown(newTotalSupply + 1, newTotalAssets + 1);
    }

    function previewRedeem(uint256 shares) public view returns (uint256) {
        (uint256 performanceFeeShares, uint256 managementFeeShares, uint256 newTotalAssets) = accrueInterestView();
        uint256 newTotalSupply = totalSupply + performanceFeeShares + managementFeeShares;
        return shares.mulDivUp(newTotalSupply + 1, newTotalAssets + 1);
    }

    /* USER VAULT INTERACTIONS */

    function deposit(uint256 assets, address receiver) external returns (uint256) {
        accrueInterest();
        uint256 shares = previewDeposit(assets);
        enter(assets, shares, receiver);
        return shares;
    }

    function mint(uint256 shares, address receiver) external returns (uint256) {
        accrueInterest();
        uint256 assets = previewMint(shares);
        enter(assets, shares, receiver);
        return assets;
    }

    function enter(uint256 assets, uint256 shares, address receiver) internal {
        require(gate == address(0) || IGate(gate).canUseShares(receiver), ErrorsLib.Unauthorized());
        SafeERC20Lib.safeTransferFrom(asset, msg.sender, address(this), assets);
        createShares(receiver, shares);
        totalAssets += assets;

        try this.reallocateFromIdle(liquidityAdapter, liquidityData, assets) {} catch {}
    }

    function withdraw(uint256 assets, address receiver, address onBehalf) external returns (uint256) {
        accrueInterest();
        uint256 shares = previewWithdraw(assets);
        exit(assets, shares, receiver, onBehalf);
        return shares;
    }

    function redeem(uint256 shares, address receiver, address onBehalf) external returns (uint256) {
        accrueInterest();
        uint256 assets = previewRedeem(shares);
        exit(assets, shares, receiver, onBehalf);
        return assets;
    }

    function exit(uint256 assets, uint256 shares, address receiver, address onBehalf) internal {
        require(
            gate == address(0) || (IGate(gate).canUseShares(onBehalf) && IGate(gate).canReceiveAssets(receiver)),
            ErrorsLib.Unauthorized()
        );
        uint256 idleAssets = IERC20(asset).balanceOf(address(this));
        if (assets > idleAssets && liquidityAdapter != address(0)) {
            this.reallocateToIdle(liquidityAdapter, liquidityData, assets - idleAssets);
        }
        uint256 _allowance = allowance[onBehalf][msg.sender];
        if (msg.sender != onBehalf && _allowance != type(uint256).max) {
            allowance[onBehalf][msg.sender] = _allowance - shares;
        }
        deleteShares(onBehalf, shares);
        totalAssets -= assets;

        for (uint256 i; i < idsWithRelativeCap.length; i++) {
            bytes32 id = idsWithRelativeCap[i];
            require(allocation[id] <= totalAssets.mulDivDown(relativeCap[id], WAD), ErrorsLib.RelativeCapExceeded());
        }

        SafeERC20Lib.safeTransfer(asset, receiver, assets);
    }

    /* ERC20 */

    function transfer(address to, uint256 amount) external returns (bool) {
        require(to != address(0), ErrorsLib.ZeroAddress());
        require(
            gate == address(0) || (IGate(gate).canUseShares(msg.sender) && IGate(gate).canUseShares(to)),
            ErrorsLib.Unauthorized()
        );
        balanceOf[msg.sender] -= amount;
        balanceOf[to] += amount;
        emit EventsLib.Transfer(msg.sender, to, amount);
        return true;
    }

    function transferFrom(address from, address to, uint256 amount) external returns (bool) {
        require(from != address(0), ErrorsLib.ZeroAddress());
        require(to != address(0), ErrorsLib.ZeroAddress());
        require(
            gate == address(0) || (IGate(gate).canUseShares(from) && IGate(gate).canUseShares(to)),
            ErrorsLib.Unauthorized()
        );
        uint256 _allowance = allowance[from][msg.sender];

        if (_allowance < type(uint256).max) allowance[from][msg.sender] = _allowance - amount;

        balanceOf[from] -= amount;
        balanceOf[to] += amount;
        emit EventsLib.Transfer(from, to, amount);

        return true;
    }

    function approve(address spender, uint256 amount) external returns (bool) {
        allowance[msg.sender][spender] = amount;
        emit EventsLib.Approval(msg.sender, spender, amount);
        return true;
    }

    function permit(address _owner, address spender, uint256 value, uint256 deadline, uint8 v, bytes32 r, bytes32 s)
        external
    {
        require(deadline >= block.timestamp, ErrorsLib.PermitDeadlineExpired());

        bytes32 hashStruct = keccak256(abi.encode(PERMIT_TYPEHASH, _owner, spender, value, nonces[_owner]++, deadline));
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", DOMAIN_SEPARATOR(), hashStruct));
        address recoveredAddress = ecrecover(digest, v, r, s);
        require(recoveredAddress != address(0) && recoveredAddress == _owner, ErrorsLib.InvalidSigner());

        allowance[_owner][spender] = value;
        emit EventsLib.Approval(_owner, spender, value);
    }

    function DOMAIN_SEPARATOR() public view returns (bytes32) {
        return keccak256(abi.encode(DOMAIN_TYPEHASH, block.chainid, address(this)));
    }

    function createShares(address to, uint256 amount) internal {
        require(to != address(0), ErrorsLib.ZeroAddress());
        balanceOf[to] += amount;
        totalSupply += amount;
        emit EventsLib.Transfer(address(0), to, amount);
    }

    function deleteShares(address from, uint256 amount) internal {
        require(from != address(0), ErrorsLib.ZeroAddress());
        balanceOf[from] -= amount;
        totalSupply -= amount;
        emit EventsLib.Transfer(from, address(0), amount);
    }
}
