// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.28;

import {IVaultV2, IERC20, ExitRequest} from "./interfaces/IVaultV2.sol";
import {IAdapter} from "./interfaces/IAdapter.sol";
import {IVic} from "./interfaces/IVic.sol";

import {ErrorsLib} from "./libraries/ErrorsLib.sol";
import {EventsLib} from "./libraries/EventsLib.sol";
import "./libraries/ConstantsLib.sol";
import {MathLib} from "./libraries/MathLib.sol";
import {SafeERC20Lib} from "./libraries/SafeERC20Lib.sol";
import "forge-std/console.sol";

/// @dev Zero checks are not performed.
/// @dev No-ops are allowed.
contract VaultV2 is IVaultV2 {
    using MathLib for uint256;

    /* IMMUTABLE */
    address public immutable asset;

    /* ROLES STORAGE */
    address public owner;
    address public curator;
    mapping(address => bool) public isSentinel;
    mapping(address => bool) public isAllocator;

    /* TOKEN STORAGE */
    uint256 public totalSupply;
    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;
    mapping(address => uint256) public nonces;

    /* CURATION AND ALLOCATION STORAGE */
    uint256 public totalAssets;
    uint96 public lastUpdate;
    address public vic;
    uint256 public forceDeallocatePenalty;
    /// @dev Adapter is trusted to pass the expected ids when supplying assets.
    mapping(address => bool) public isAdapter;
    /// @dev Key is an abstract id, which can represent a protocol, a collateral, a duration etc.
    mapping(bytes32 => uint256) public absoluteCap;
    /// @dev Key is an abstract id, which can represent a protocol, a collateral, a duration etc.
    /// @dev The relative cap is relative to `totalAssets`.
    /// @dev Units are in WAD.
    /// @dev A relative cap of 1 WAD means no relative cap.
    mapping(bytes32 => uint256) internal oneMinusRelativeCap;
    /// @dev Useful to iterate over all ids with relative cap in withdrawals.
    bytes32[] public idsWithRelativeCap;
    /// @dev Interests are not counted in the allocation.
    mapping(bytes32 => uint256) public allocation;
    /// @dev calldata => executable at
    mapping(bytes => uint256) public validAt;
    /// @dev function selector => timelock duration
    mapping(bytes4 => uint256) public timelock;
    address public liquidityAdapter;
    bytes public liquidityData;

    /* FEES STORAGE */
    /// @dev invariant: performanceFee != 0 => performanceFeeRecipient != address(0)
    uint96 public performanceFee;
    address public performanceFeeRecipient;
    /// @dev invariant: managementFee != 0 => managementFeeRecipient != address(0)
    uint96 public managementFee;
    address public managementFeeRecipient;
    /// @dev invariant: exitFee != 0 => exitFeeRecipient != address(0)
    uint96 public exitFee;
    address public exitFeeRecipient;

    /* GETTERS */

    function idsWithRelativeCapLength() public view returns (uint256) {
        return idsWithRelativeCap.length;
    }

    function relativeCap(bytes32 id) public view returns (uint256) {
        return WAD - oneMinusRelativeCap[id];
    }

    /* MULTICALL */

    function multicall(bytes[] calldata data) external {
        for (uint256 i = 0; i < data.length; i++) {
            (bool success, bytes memory returnData) = address(this).delegatecall(data[i]);
            if (!success) {
                assembly ("memory-safe") {
                    revert(add(32, returnData), mload(returnData))
                }
            }
        }
    }

    mapping(address => mapping(address => bool)) public canRequestExit;
    mapping(address => ExitRequest) public exitRequests;

    // Not updated by share price changes.
    // May create deadweight idle assets if share price goes down, until a) it comes back up or b) until all exit claims
    // have been processed.
    uint256 public totalMaxExitAssets;

    uint256 public maxMissingExitAssetsDuration = 12 weeks;
    // Can become incorrect as share price moves.
    uint256 public missingExitAssetsSince;

    /* CONSTRUCTOR */

    constructor(address _owner, address _asset) {
        asset = _asset;
        owner = _owner;
        lastUpdate = uint96(block.timestamp);
        timelock[IVaultV2.decreaseTimelock.selector] = TIMELOCK_CAP;
        emit EventsLib.Constructor(_owner, _asset);
    }

    /* OWNER ACTIONS */

    function setOwner(address newOwner) external {
        require(msg.sender == owner, ErrorsLib.Unauthorized());
        owner = newOwner;
        emit EventsLib.SetOwner(newOwner);
    }

    function setCurator(address newCurator) external {
        require(msg.sender == owner, ErrorsLib.Unauthorized());
        curator = newCurator;
        emit EventsLib.SetCurator(newCurator);
    }

    function setIsSentinel(address account, bool newIsSentinel) external {
        require(msg.sender == owner, ErrorsLib.Unauthorized());
        isSentinel[account] = newIsSentinel;
        emit EventsLib.SetIsSentinel(account, newIsSentinel);
    }

    /* CURATOR ACTIONS */

    function setIsAllocator(address account, bool newIsAllocator) external timelocked {
        isAllocator[account] = newIsAllocator;
        emit EventsLib.SetIsAllocator(account, newIsAllocator);
    }

    function setVic(address newVic) external timelocked {
        accrueInterest();
        vic = newVic;
        emit EventsLib.SetVic(newVic);
    }

    function setIsAdapter(address account, bool newIsAdapter) external timelocked {
        if (!newIsAdapter) require(updateMissingExitAssets() <= 0, ErrorsLib.MissingExitAssets());
        require(account != liquidityAdapter, ErrorsLib.LiquidityAdapterInvariantBroken());
        isAdapter[account] = newIsAdapter;
        emit EventsLib.SetIsAdapter(account, newIsAdapter);
    }

    function increaseTimelock(bytes4 selector, uint256 newDuration) external {
        require(msg.sender == curator, ErrorsLib.Unauthorized());
        require(selector != IVaultV2.decreaseTimelock.selector, ErrorsLib.TimelockCapIsFixed());
        require(newDuration <= TIMELOCK_CAP, ErrorsLib.TimelockDurationTooHigh());
        require(newDuration >= timelock[selector], ErrorsLib.TimelockNotIncreasing());

        timelock[selector] = newDuration;
        emit EventsLib.IncreaseTimelock(selector, newDuration);
    }

    function decreaseTimelock(bytes4 selector, uint256 newDuration) external timelocked {
        require(selector != IVaultV2.decreaseTimelock.selector, ErrorsLib.TimelockCapIsFixed());
        require(newDuration <= timelock[selector], ErrorsLib.TimelockNotDecreasing());

        timelock[selector] = newDuration;
        emit EventsLib.DecreaseTimelock(selector, newDuration);
    }

    function setPerformanceFee(uint256 newPerformanceFee) external timelocked {
        require(newPerformanceFee <= MAX_PERFORMANCE_FEE, ErrorsLib.FeeTooHigh());
        require(performanceFeeRecipient != address(0) || newPerformanceFee == 0, ErrorsLib.FeeInvariantBroken());

        accrueInterest();

        performanceFee = uint96(newPerformanceFee); // Safe because 2**96 > MAX_PERFORMANCE_FEE.
        emit EventsLib.SetPerformanceFee(newPerformanceFee);
    }

    function setManagementFee(uint256 newManagementFee) external timelocked {
        require(newManagementFee <= MAX_MANAGEMENT_FEE, ErrorsLib.FeeTooHigh());
        require(managementFeeRecipient != address(0) || newManagementFee == 0, ErrorsLib.FeeInvariantBroken());

        accrueInterest();

        managementFee = uint96(newManagementFee); // Safe because 2**96 > MAX_MANAGEMENT_FEE.
        emit EventsLib.SetManagementFee(newManagementFee);
    }

    function setExitFee(uint256 newExitFee) external timelocked {
        require(newExitFee < WAD, ErrorsLib.ExitFeeTooHigh());
        require(exitFeeRecipient != address(0), ErrorsLib.FeeInvariantBroken());

        if (newExitFee > exitFee) require(updateMissingExitAssets() <= 0, ErrorsLib.MissingExitAssets());

        // safe cast because newExitFee < WAD < type(uint96).max
        exitFee = uint96(newExitFee);
    }

    /* CURATOR ACTIONS */
    function setPerformanceFeeRecipient(address newPerformanceFeeRecipient) external timelocked {
        require(newPerformanceFeeRecipient != address(0) || performanceFee == 0, ErrorsLib.FeeInvariantBroken());

        accrueInterest();

        performanceFeeRecipient = newPerformanceFeeRecipient;
        emit EventsLib.SetPerformanceFeeRecipient(newPerformanceFeeRecipient);
    }

    function setManagementFeeRecipient(address newManagementFeeRecipient) external timelocked {
        require(newManagementFeeRecipient != address(0) || managementFee == 0, ErrorsLib.FeeInvariantBroken());

        accrueInterest();

        managementFeeRecipient = newManagementFeeRecipient;
        emit EventsLib.SetManagementFeeRecipient(newManagementFeeRecipient);
    }

    function setExitFeeRecipient(address newExitFeeRecipient) external timelocked {
        require(newExitFeeRecipient != address(0) || exitFee == 0, ErrorsLib.FeeInvariantBroken());
        exitFeeRecipient = newExitFeeRecipient;
    }

    function increaseAbsoluteCap(bytes memory idData, uint256 newAbsoluteCap) external timelocked {
        bytes32 id = keccak256(idData);
        require(newAbsoluteCap >= absoluteCap[id], ErrorsLib.AbsoluteCapNotIncreasing());

        absoluteCap[id] = newAbsoluteCap;
        emit EventsLib.IncreaseAbsoluteCap(id, idData, newAbsoluteCap);
    }

    function decreaseAbsoluteCap(bytes memory idData, uint256 newAbsoluteCap) external {
        require(msg.sender == curator || isSentinel[msg.sender], ErrorsLib.Unauthorized());
        bytes32 id = keccak256(idData);
        require(newAbsoluteCap <= absoluteCap[id], ErrorsLib.AbsoluteCapNotDecreasing());

        absoluteCap[id] = newAbsoluteCap;
        emit EventsLib.DecreaseAbsoluteCap(id, idData, newAbsoluteCap);
    }

    function increaseRelativeCap(bytes memory idData, uint256 newRelativeCap) external timelocked {
        bytes32 id = keccak256(idData);
        require(newRelativeCap <= WAD, ErrorsLib.RelativeCapAboveOne());
        require(newRelativeCap >= relativeCap(id), ErrorsLib.RelativeCapNotIncreasing());

        if (newRelativeCap > relativeCap(id)) {
            if (newRelativeCap == WAD) {
                uint256 i;
                while (idsWithRelativeCap[i] != id) i++;
                idsWithRelativeCap[i] = idsWithRelativeCap[idsWithRelativeCap.length - 1];
                idsWithRelativeCap.pop();
            }

            oneMinusRelativeCap[id] = WAD - newRelativeCap;
        }

        emit EventsLib.IncreaseRelativeCap(id, idData, newRelativeCap);
    }

    function decreaseRelativeCap(bytes memory idData, uint256 newRelativeCap) external timelocked {
        bytes32 id = keccak256(idData);
        // To set a cap to 0, use `decreaseAbsoluteCap`.
        require(newRelativeCap > 0, ErrorsLib.RelativeCapZero());
        require(newRelativeCap <= relativeCap(id), ErrorsLib.RelativeCapNotDecreasing());

        if (newRelativeCap < relativeCap(id)) {
            require(allocation[id] <= totalAssets.mulDivDown(newRelativeCap, WAD), ErrorsLib.RelativeCapExceeded());

            if (relativeCap(id) == WAD) idsWithRelativeCap.push(id);

            oneMinusRelativeCap[id] = WAD - newRelativeCap;
        }

        emit EventsLib.DecreaseRelativeCap(id, idData, newRelativeCap);
    }

    function setForceDeallocatePenalty(uint256 newForceDeallocatePenalty) external timelocked {
        require(newForceDeallocatePenalty <= MAX_FORCE_DEALLOCATE_PENALTY, ErrorsLib.PenaltyTooHigh());
        forceDeallocatePenalty = newForceDeallocatePenalty;
        emit EventsLib.SetForceDeallocatePenalty(newForceDeallocatePenalty);
    }

    function setMaxMissingExitAssetsDuration(uint256 newMaxMissingExitAssetsDuration) external timelocked {
        if (newMaxMissingExitAssetsDuration > maxMissingExitAssetsDuration) {
            require(updateMissingExitAssets() <= 0, ErrorsLib.MissingExitAssets());
        }

        maxMissingExitAssetsDuration = newMaxMissingExitAssetsDuration;
    }

    /* ALLOCATOR ACTIONS */

    function allocate(address adapter, bytes memory data, uint256 assets) external {
        require(isAllocator[msg.sender] || msg.sender == address(this), ErrorsLib.NotAllocator());
        require(isAdapter[adapter], ErrorsLib.NotAdapter());

        SafeERC20Lib.safeTransfer(asset, adapter, assets);
        bytes32[] memory ids = IAdapter(adapter).allocate(data, assets);

        require(updateMissingExitAssets() <= 0, ErrorsLib.MissingExitAssets());

        for (uint256 i; i < ids.length; i++) {
            allocation[ids[i]] += assets;

            require(allocation[ids[i]] <= absoluteCap[ids[i]], ErrorsLib.AbsoluteCapExceeded());
            if (relativeCap(ids[i]) < WAD) {
                require(
                    allocation[ids[i]] <= totalAssets.mulDivDown(relativeCap(ids[i]), WAD),
                    ErrorsLib.RelativeCapExceeded()
                );
            }
        }
        emit EventsLib.Allocate(msg.sender, adapter, assets, ids);
    }

    // Do not try to redeem normally first
    function requestExit(uint256 requestedShares, address supplier) external {
        if (msg.sender != supplier) require(canRequestExit[supplier][msg.sender], ErrorsLib.Unauthorized());

        ExitRequest storage request = exitRequests[supplier];
        uint256 exitShares = requestedShares.mulDivUp(WAD - exitFee, WAD);
        uint256 exitAssets = previewRedeem(exitShares);

        deleteShares(supplier, exitShares);
        _transfer(supplier, exitFeeRecipient, requestedShares - exitShares);
        request.shares += exitShares;
        request.maxAssets += exitAssets;
        totalMaxExitAssets += exitAssets;
        totalAssets -= exitAssets;

        updateMissingExitAssets();
    }

    function claimExit(uint256 claimedShares, address receiver, address supplier)
        external
        returns (uint256 exitAssets)
    {
        uint256 _allowance = allowance[supplier][msg.sender];
        if (msg.sender != supplier && _allowance != type(uint256).max) {
            if (_allowance < type(uint256).max) allowance[supplier][msg.sender] = _allowance - claimedShares;
        }

        ExitRequest storage request = exitRequests[supplier];
        uint256 claimedAssets = request.maxAssets.mulDivUp(claimedShares, request.shares);
        uint256 quotedClaimedShares = previewRedeem(claimedShares);
        exitAssets = MathLib.min(claimedAssets, quotedClaimedShares);

        request.shares -= claimedShares;
        request.maxAssets = request.maxAssets.zeroFloorSub(claimedAssets);
        totalMaxExitAssets = totalMaxExitAssets.zeroFloorSub(claimedAssets);
        IERC20(asset).transfer(receiver, exitAssets);

        updateMissingExitAssets();
    }

    function approveExit(address spender, bool allowed) external {
        canRequestExit[msg.sender][spender] = allowed;
    }

    function deallocate(address adapter, bytes memory data, uint256 assets) external {
        require(
            isAllocator[msg.sender] || isSentinel[msg.sender] || msg.sender == address(this)
                || (missingExitAssetsSince != 0 && block.timestamp - missingExitAssetsSince <= maxMissingExitAssetsDuration),
            ErrorsLib.NotAllocator()
        );
        require(isAdapter[adapter], ErrorsLib.NotAdapter());

        bytes32[] memory ids = IAdapter(adapter).deallocate(data, assets);

        updateMissingExitAssets();

        for (uint256 i; i < ids.length; i++) {
            allocation[ids[i]] = allocation[ids[i]].zeroFloorSub(assets);
        }

        SafeERC20Lib.safeTransferFrom(asset, adapter, address(this), assets);
        emit EventsLib.Deallocate(msg.sender, adapter, assets, ids);
    }

    function setLiquidityAdapter(address newLiquidityAdapter) external {
        require(isAllocator[msg.sender], ErrorsLib.Unauthorized());
        require(
            newLiquidityAdapter == address(0) || isAdapter[newLiquidityAdapter],
            ErrorsLib.LiquidityAdapterInvariantBroken()
        );
        liquidityAdapter = newLiquidityAdapter;
        emit EventsLib.SetLiquidityAdapter(msg.sender, newLiquidityAdapter);
    }

    function setLiquidityData(bytes memory newLiquidityData) external {
        require(isAllocator[msg.sender], ErrorsLib.Unauthorized());
        liquidityData = newLiquidityData;
        emit EventsLib.SetLiquidityData(msg.sender, newLiquidityData);
    }

    /* TIMELOCKS */

    function submit(bytes calldata data) external {
        require(msg.sender == curator, ErrorsLib.Unauthorized());
        require(validAt[data] == 0, ErrorsLib.DataAlreadyPending());

        bytes4 selector = bytes4(data);
        validAt[data] = block.timestamp + timelock[selector];
        emit EventsLib.Submit(msg.sender, selector, data, validAt[data]);
    }

    modifier timelocked() {
        require(validAt[msg.data] != 0, ErrorsLib.DataNotTimelocked());
        require(block.timestamp >= validAt[msg.data], ErrorsLib.TimelockNotExpired());
        validAt[msg.data] = 0;
        _;
    }

    function revoke(bytes calldata data) external {
        require(msg.sender == curator || isSentinel[msg.sender], ErrorsLib.Unauthorized());
        require(validAt[data] != 0, ErrorsLib.DataNotTimelocked());
        validAt[data] = 0;
        emit EventsLib.Revoke(msg.sender, bytes4(data), data);
    }

    /* EXCHANGE RATE */

    function accrueInterest() public {
        (uint256 newTotalAssets, uint256 performanceFeeShares, uint256 managementFeeShares) = accrueInterestView();
        emit EventsLib.AccrueInterest(totalAssets, newTotalAssets, performanceFeeShares, managementFeeShares);
        totalAssets = newTotalAssets;
        if (performanceFeeShares != 0) createShares(performanceFeeRecipient, performanceFeeShares);
        if (managementFeeShares != 0) createShares(managementFeeRecipient, managementFeeShares);
        lastUpdate = uint96(block.timestamp);
    }

    function accrueInterestView() public view returns (uint256, uint256, uint256) {
        uint256 elapsed = block.timestamp - lastUpdate;
        if (elapsed == 0) return (totalAssets, 0, 0);
        uint256 interestPerSecond;
        try IVic(vic).interestPerSecond(totalAssets, elapsed) returns (uint256 output) {
            if (output <= totalAssets.mulDivDown(MAX_RATE_PER_SECOND, WAD)) interestPerSecond = output;
            else interestPerSecond = 0;
        } catch {
            interestPerSecond = 0;
        }
        uint256 interest = interestPerSecond * elapsed;
        uint256 newTotalAssets = totalAssets + interest;

        uint256 performanceFeeShares;
        uint256 managementFeeShares;
        // Note: the fee assets is subtracted from the total assets in the fee shares calculation to compensate for the
        // fact that total assets is already increased by the total interest (including the fee assets).
        // Note: `feeAssets` may be rounded down to 0 if `totalInterest * fee < WAD`.
        if (interest > 0 && performanceFee != 0) {
            // Note: the accrued performance fee might be smaller than this because of the management fee.
            uint256 performanceFeeAssets = interest.mulDivDown(performanceFee, WAD);
            performanceFeeShares =
                performanceFeeAssets.mulDivDown(totalSupply + 1, newTotalAssets + 1 - performanceFeeAssets);
        }
        if (managementFee != 0) {
            // Note: The vault must be pinged at least once every 20 years to avoid management fees exceeding total
            // assets and revert forever.
            // Note: The management fee is taken on newTotalAssets to make all approximations consistent (interacting
            // less increases management fees).
            uint256 managementFeeAssets = (newTotalAssets * elapsed).mulDivDown(managementFee, WAD);
            managementFeeShares = managementFeeAssets.mulDivDown(
                totalSupply + 1 + performanceFeeShares, newTotalAssets + 1 - managementFeeAssets
            );
        }
        return (newTotalAssets, performanceFeeShares, managementFeeShares);
    }

    function previewDeposit(uint256 assets) public view returns (uint256) {
        (uint256 newTotalAssets, uint256 performanceFeeShares, uint256 managementFeeShares) = accrueInterestView();
        uint256 newTotalSupply = totalSupply + performanceFeeShares + managementFeeShares;
        return assets.mulDivDown(newTotalSupply + 1, newTotalAssets + 1);
    }

    function previewWithdraw(uint256 assets) public view returns (uint256) {
        (uint256 newTotalAssets, uint256 performanceFeeShares, uint256 managementFeeShares) = accrueInterestView();
        uint256 newTotalSupply = totalSupply + performanceFeeShares + managementFeeShares;
        return assets.mulDivUp(newTotalSupply + 1, newTotalAssets + 1);
    }

    function previewMint(uint256 shares) public view returns (uint256) {
        (uint256 newTotalAssets, uint256 performanceFeeShares, uint256 managementFeeShares) = accrueInterestView();
        uint256 newTotalSupply = totalSupply + performanceFeeShares + managementFeeShares;
        return shares.mulDivUp(newTotalAssets + 1, newTotalSupply + 1);
    }

    function previewRedeem(uint256 shares) public view returns (uint256) {
        (uint256 newTotalAssets, uint256 performanceFeeShares, uint256 managementFeeShares) = accrueInterestView();
        uint256 newTotalSupply = totalSupply + performanceFeeShares + managementFeeShares;
        return shares.mulDivDown(newTotalAssets + 1, newTotalSupply + 1);
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

    // Negative value means idle assets availabel for withdrawal.
    function updateMissingExitAssets() public returns (int256 missingExitAssets) {
        int256 idleAssets = int(MathLib.min(uint(type(int256).max),IERC20(asset).balanceOf(address(this))));
        console.log(totalMaxExitAssets);
        console.log(idleAssets);
        missingExitAssets = int256(totalMaxExitAssets) - idleAssets;

        if (missingExitAssets <= 0) {
            // can only happen when called by requestExit
            missingExitAssetsSince = 0;
        } else if (missingExitAssetsSince == 0) {
            missingExitAssetsSince = block.timestamp;
        }
    }

    function enter(uint256 assets, uint256 shares, address receiver) internal {
        SafeERC20Lib.safeTransferFrom(asset, msg.sender, address(this), assets);
        createShares(receiver, shares);
        totalAssets += assets;

        int256 missingAssets = updateMissingExitAssets();
        if (missingAssets <= 0 && liquidityAdapter != address(0)) {
            uint256 toReallocate = MathLib.min(uint256(-missingAssets), assets);
            try this.allocate(liquidityAdapter, liquidityData, assets) {} catch {}
        }
        emit EventsLib.Deposit(msg.sender, receiver, assets, shares);
    }

    function withdraw(uint256 assets, address receiver, address onBehalf) public returns (uint256) {
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
        int256 missingAssets = int256(assets);

        if (missingAssets > 0 && liquidityAdapter != address(0)) {
            this.deallocate(liquidityAdapter, liquidityData, uint256(missingAssets));
        }

        if (msg.sender != onBehalf) {
            uint256 _allowance = allowance[onBehalf][msg.sender];
            if (_allowance != type(uint256).max) allowance[onBehalf][msg.sender] = _allowance - shares;
        }

        deleteShares(onBehalf, shares);
        totalAssets -= assets;

        for (uint256 i; i < idsWithRelativeCap.length; i++) {
            bytes32 id = idsWithRelativeCap[i];
            // relativeCap(id) < WAD is true for all ids in idsWithRelativeCap
            require(allocation[id] <= totalAssets.mulDivDown(relativeCap(id), WAD), ErrorsLib.RelativeCapExceeded());
        }

        SafeERC20Lib.safeTransfer(asset, receiver, assets);
        emit EventsLib.Withdraw(msg.sender, receiver, onBehalf, assets, shares);
    }

    /// @dev Loop to make the relative cap check at the end.
    function forceDeallocate(address[] memory adapters, bytes[] memory data, uint256[] memory assets, address onBehalf)
        external
        returns (uint256)
    {
        require(adapters.length == data.length && adapters.length == assets.length, ErrorsLib.InvalidInputLength());
        uint256 total;
        for (uint256 i; i < adapters.length; i++) {
            this.deallocate(adapters[i], data[i], assets[i]);
            total += assets[i];
        }

        // The penalty is taken as a withdrawal that is donated to the vault.
        uint256 shares = withdraw(total.mulDivDown(forceDeallocatePenalty, WAD), address(this), onBehalf);
        emit EventsLib.ForceDeallocate(msg.sender, onBehalf, total);
        return shares;
    }

    /* ERC20 */

    // if (selector == IVaultV2.setExitFeeRecipient.selector) return sender == owner;
    // if (selector == IVaultV2.setExitFee.selector) return sender == treasurer;
    function transfer(address to, uint256 shares) external returns (bool) {
        require(to != address(0), ErrorsLib.ZeroAddress());
        _transfer(msg.sender, to, shares);
        return true;
    }

    function transferFrom(address from, address to, uint256 shares) external returns (bool) {
        require(from != address(0), ErrorsLib.ZeroAddress());
        require(to != address(0), ErrorsLib.ZeroAddress());

        if (msg.sender != from) {
            uint256 _allowance = allowance[from][msg.sender];
            if (_allowance != type(uint256).max) {
                allowance[from][msg.sender] = _allowance - shares;
                emit EventsLib.AllowanceUpdatedByTransferFrom(from, msg.sender, _allowance - shares);
            }
        }

        _transfer(from, to, shares);
        return true;
    }

    function _transfer(address from, address to, uint256 amount) internal {
        balanceOf[from] -= amount;
        balanceOf[to] += amount;
        emit EventsLib.Transfer(from, to, amount);
    }

    function approve(address spender, uint256 shares) external returns (bool) {
        allowance[msg.sender][spender] = shares;
        emit EventsLib.Approval(msg.sender, spender, shares);
        return true;
    }

    function permit(address _owner, address spender, uint256 shares, uint256 deadline, uint8 v, bytes32 r, bytes32 s)
        external
    {
        require(deadline >= block.timestamp, ErrorsLib.PermitDeadlineExpired());

        uint256 nonce = nonces[_owner]++;
        bytes32 hashStruct = keccak256(abi.encode(PERMIT_TYPEHASH, _owner, spender, shares, nonce, deadline));
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", DOMAIN_SEPARATOR(), hashStruct));
        address recoveredAddress = ecrecover(digest, v, r, s);
        require(recoveredAddress != address(0) && recoveredAddress == _owner, ErrorsLib.InvalidSigner());

        allowance[_owner][spender] = shares;
        emit EventsLib.Approval(_owner, spender, shares);
        emit EventsLib.Permit(_owner, spender, shares, nonce, deadline);
    }

    function DOMAIN_SEPARATOR() public view returns (bytes32) {
        return keccak256(abi.encode(DOMAIN_TYPEHASH, block.chainid, address(this)));
    }

    function createShares(address to, uint256 shares) internal {
        require(to != address(0), ErrorsLib.ZeroAddress());
        balanceOf[to] += shares;
        totalSupply += shares;
        emit EventsLib.Transfer(address(0), to, shares);
    }

    function deleteShares(address from, uint256 shares) internal {
        require(from != address(0), ErrorsLib.ZeroAddress());
        balanceOf[from] -= shares;
        totalSupply -= shares;
        emit EventsLib.Transfer(from, address(0), shares);
    }
}
