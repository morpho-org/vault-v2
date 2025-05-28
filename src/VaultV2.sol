// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.28;

import {IVaultV2, IERC20} from "./interfaces/IVaultV2.sol";
import {IAdapter} from "./interfaces/IAdapter.sol";
import {IVic} from "./interfaces/IVic.sol";

import {ErrorsLib} from "./libraries/ErrorsLib.sol";
import {EventsLib} from "./libraries/EventsLib.sol";
import "./libraries/ConstantsLib.sol";
import {MathLib} from "./libraries/MathLib.sol";
import {UtilsLib} from "./libraries/UtilsLib.sol";
import {SafeERC20Lib} from "./libraries/SafeERC20Lib.sol";
import {ISharesGate, IReceiveAssetsGate, ISendAssetsGate} from "./interfaces/IGate.sol";

/// @dev Not ERC-4626 compliant due to missing functions and `totalAssets()` is not up to date.
/// @dev Zero checks are not systematically performed.
/// @dev No-ops are allowed.
/// @dev Natspec are specified only when it brings clarity.
/// @dev The vault has 1 virtual asset and a decimals offset of 0.
/// See https://docs.openzeppelin.com/contracts/5.x/erc4626#inflation-attack
/// @dev Roles are not "two-step" so one must check if they really have this role.
/// @dev The shares are represented with ERC-20, also compliant with ERC-2612 (permit extension).
/// @dev To accrue interest, the vault queries the Vault Interest Controller (VIC) which returns the interest per second
/// that must be distributed on the period (since `lastUpdate`). The VIC must be chosen and managed carefully to not
/// distribute more than what the vault's investments are earning.
/// @dev Vault shares should not be loanable to prevent shares shorting on loss realization. Shares can be flashloanable
/// because flashloan based shorting is prevented.
/// @dev Loose specification of adapters:
/// - They must enforce that only the vault can call allocate/deallocate.
/// - They must enter/exit markets only in allocate/deallocate.
/// - They must return the right ids on allocate/deallocate.
/// - They must have approved `assets` for the vault at the end of deallocate.
/// - They must make it possible to make deallocate possible (for in-kind redemptions).
/// @dev Liquidity market:
/// - `liquidityAdapter` is allocated to on deposit/mint, and deallocated from on withdraw/redeem if idle assets don't
/// cover the withdraw.
/// - The liquidity market is mostly useful on exit, so that exit liquidity is available in addition to the idle assets.
/// But the same adapter/data is used for both entry and exit to have the property that in the general case looping
/// supply-withdraw or withdraw-supply should not change the allocation.
contract VaultV2 is IVaultV2 {
    using MathLib for uint256;

    /* IMMUTABLE */

    address public immutable asset;

    /* ROLES STORAGE */

    address public owner;
    address public curator;
    /// @notice Gates sending and receiving shares.
    address public sharesGate;
    /// @notice Gates receiving assets from the vault.
    address public receiveAssetsGate;
    /// @notice Gates depositing assets to the vault.
    address public sendAssetsGate;

    mapping(address account => bool) public isSentinel;
    mapping(address account => bool) public isAllocator;

    /* TOKEN STORAGE */

    uint256 public totalSupply;
    mapping(address account => uint256) public balanceOf;
    mapping(address owner => mapping(address spender => uint256)) public allowance;
    mapping(address account => uint256) public nonces;

    /* INTEREST STORAGE */

    uint192 internal _totalAssets;
    uint64 public lastUpdate;
    address public vic;
    /// @dev Prevents floashloan-based shorting of vault shares during loss realizations.
    bool public transient enterBlocked;

    /* CURATION STORAGE */

    mapping(address account => bool) public isAdapter;
    /// @dev The allocation is not updated to take interests into account.
    /// @dev Some underlying markets might allow to take into account interest (fixed rate, fixed term), some might not.
    mapping(bytes32 id => uint256) public allocation;

    /// @dev The absolute cap is checked on allocate (where allocations can increase) for the ids returned by the
    /// adapter.
    mapping(bytes32 id => uint256) public absoluteCap;

    /// @dev Unit is WAD.
    /// @dev The relative cap is relative to `totalAssets`.
    /// @dev Relative caps are "soft" in the sense that they are only checked on allocate for the ids returned by the
    /// adapter.
    mapping(bytes32 id => uint256) public relativeCap;

    mapping(address adapter => uint256) public forceDeallocatePenalty;

    /* LIQUIDITY ADAPTER STORAGE */

    /// @dev This invariant holds: liquidityAdapter != address(0) => isAdapter[liquidityAdapter].
    address public liquidityAdapter;
    bytes public liquidityData;

    /* TIMELOCKS STORAGE */

    /// @dev The timelock of decreaseTimelock is hard-coded at TIMELOCK_CAP.
    /// @dev Only functions with the modifier `timelocked` are timelocked.
    /// @dev Multiple clashing data can be pending, for example increaseCap and decreaseCap, which can make so accepted
    /// timelocked data can potentially be changed shortly afterwards.
    /// @dev The minimum time in which a function can be called is the following:
    /// min(
    ///     timelock[selector],
    ///     executableAt[selector::_],
    ///     executableAt[decreaseTimelock::selector::newTimelock] + newTimelock
    /// ).
    mapping(bytes4 selector => uint256) public timelock;

    /// @dev Nothing is checked on the timelocked data, so it could be not executable (function does not exist,
    /// conditions are not met, etc.).
    mapping(bytes data => uint256) public executableAt;

    /* FEES STORAGE */

    /// @dev Fees unit is WAD.
    /// @dev This invariant holds for both fees: fee != 0 => recipient != address(0).
    uint96 public performanceFee;
    address public performanceFeeRecipient;
    /// @dev Fees unit is WAD.
    /// @dev This invariant holds for both fees: fee != 0 => recipient != address(0).
    uint96 public managementFee;
    address public managementFeeRecipient;

    /* GETTERS */

    function totalAssets() external view returns (uint256) {
        return _totalAssets;
    }

    function DOMAIN_SEPARATOR() public view returns (bytes32) {
        return keccak256(abi.encode(DOMAIN_TYPEHASH, block.chainid, address(this)));
    }

    /* MULTICALL */

    /// @dev Mostly useful to batch admin actions together.
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

    /* CONSTRUCTOR */

    constructor(address _owner, address _asset) {
        asset = _asset;
        owner = _owner;
        lastUpdate = uint64(block.timestamp);
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

    function setSharesGate(address newSharesGate) external timelocked {
        sharesGate = newSharesGate;
        emit EventsLib.SetSharesGate(newSharesGate);
    }

    function setReceiveAssetsGate(address newReceiveAssetsGate) external timelocked {
        receiveAssetsGate = newReceiveAssetsGate;
        emit EventsLib.SetReceiveAssetsGate(newReceiveAssetsGate);
    }

    function setSendAssetsGate(address newSendAssetsGate) external timelocked {
        sendAssetsGate = newSendAssetsGate;
        emit EventsLib.SetSendAssetsGate(newSendAssetsGate);
    }

    function setVic(address newVic) external timelocked {
        accrueInterest();
        vic = newVic;
        emit EventsLib.SetVic(newVic);
    }

    function setIsAdapter(address account, bool newIsAdapter) external timelocked {
        require(account != liquidityAdapter, ErrorsLib.LiquidityAdapterInvariantBroken());
        isAdapter[account] = newIsAdapter;
        emit EventsLib.SetIsAdapter(account, newIsAdapter);
    }

    function increaseTimelock(bytes4 selector, uint256 newDuration) external {
        require(msg.sender == curator, ErrorsLib.Unauthorized());
        require(newDuration <= TIMELOCK_CAP, ErrorsLib.TimelockDurationTooHigh());
        require(newDuration >= timelock[selector], ErrorsLib.TimelockNotIncreasing());

        timelock[selector] = newDuration;
        emit EventsLib.IncreaseTimelock(selector, newDuration);
    }

    /// @dev Irreversibly disable submit for a selector.
    /// @dev Be particularly careful as this action is not reversible.
    /// @dev After abdicating the submission of a function, it can still be executed with previously timelocked data.
    function abdicateSubmit(bytes4 selector) external timelocked {
        timelock[selector] = type(uint256).max;
        emit EventsLib.AbdicateSubmit(selector);
    }

    function decreaseTimelock(bytes4 selector, uint256 newDuration) external timelocked {
        require(selector != IVaultV2.decreaseTimelock.selector, ErrorsLib.TimelockCapIsFixed());
        require(timelock[selector] != type(uint256).max, ErrorsLib.InfiniteTimelock());
        require(newDuration <= timelock[selector], ErrorsLib.TimelockNotDecreasing());

        timelock[selector] = newDuration;
        emit EventsLib.DecreaseTimelock(selector, newDuration);
    }

    function setPerformanceFee(uint256 newPerformanceFee) external timelocked {
        require(newPerformanceFee <= MAX_PERFORMANCE_FEE, ErrorsLib.FeeTooHigh());
        require(performanceFeeRecipient != address(0) || newPerformanceFee == 0, ErrorsLib.FeeInvariantBroken());

        accrueInterest();

        // Safe because 2**96 > MAX_PERFORMANCE_FEE.
        performanceFee = uint96(newPerformanceFee);
        emit EventsLib.SetPerformanceFee(newPerformanceFee);
    }

    function setManagementFee(uint256 newManagementFee) external timelocked {
        require(newManagementFee <= MAX_MANAGEMENT_FEE, ErrorsLib.FeeTooHigh());
        require(managementFeeRecipient != address(0) || newManagementFee == 0, ErrorsLib.FeeInvariantBroken());

        accrueInterest();

        // Safe because 2**96 > MAX_MANAGEMENT_FEE.
        managementFee = uint96(newManagementFee);
        emit EventsLib.SetManagementFee(newManagementFee);
    }

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

    function increaseAbsoluteCap(bytes memory idData, uint256 newAbsoluteCap) external timelocked {
        bytes32 id = keccak256(idData);
        require(newAbsoluteCap >= absoluteCap[id], ErrorsLib.AbsoluteCapNotIncreasing());

        absoluteCap[id] = newAbsoluteCap;
        emit EventsLib.IncreaseAbsoluteCap(id, idData, newAbsoluteCap);
    }

    function decreaseAbsoluteCap(bytes memory idData, uint256 newAbsoluteCap) external {
        bytes32 id = keccak256(idData);
        require(msg.sender == curator || isSentinel[msg.sender], ErrorsLib.Unauthorized());
        require(newAbsoluteCap <= absoluteCap[id], ErrorsLib.AbsoluteCapNotDecreasing());

        absoluteCap[id] = newAbsoluteCap;
        emit EventsLib.DecreaseAbsoluteCap(id, idData, newAbsoluteCap);
    }

    function increaseRelativeCap(bytes memory idData, uint256 newRelativeCap) external timelocked {
        bytes32 id = keccak256(idData);
        require(newRelativeCap <= WAD, ErrorsLib.RelativeCapAboveOne());
        require(newRelativeCap >= relativeCap[id], ErrorsLib.RelativeCapNotIncreasing());

        relativeCap[id] = newRelativeCap;

        emit EventsLib.IncreaseRelativeCap(id, idData, newRelativeCap);
    }

    function decreaseRelativeCap(bytes memory idData, uint256 newRelativeCap) external {
        bytes32 id = keccak256(idData);
        require(msg.sender == curator || isSentinel[msg.sender], ErrorsLib.Unauthorized());
        require(newRelativeCap <= relativeCap[id], ErrorsLib.RelativeCapNotDecreasing());

        relativeCap[id] = newRelativeCap;

        emit EventsLib.DecreaseRelativeCap(id, idData, newRelativeCap);
    }

    function setForceDeallocatePenalty(address adapter, uint256 newForceDeallocatePenalty) external timelocked {
        require(newForceDeallocatePenalty <= MAX_FORCE_DEALLOCATE_PENALTY, ErrorsLib.PenaltyTooHigh());
        forceDeallocatePenalty[adapter] = newForceDeallocatePenalty;
        emit EventsLib.SetForceDeallocatePenalty(adapter, newForceDeallocatePenalty);
    }

    /* ALLOCATOR ACTIONS */

    /// @dev This function will automatically realize potential losses.
    function allocate(address adapter, bytes memory data, uint256 assets) external {
        require(isAllocator[msg.sender] || msg.sender == address(this), ErrorsLib.Unauthorized());
        require(isAdapter[adapter], ErrorsLib.NotAdapter());

        accrueInterest();

        SafeERC20Lib.safeTransfer(asset, adapter, assets);
        (bytes32[] memory ids, uint256 loss) = IAdapter(adapter).allocate(data, assets);

        if (loss > 0) {
            _totalAssets = uint256(_totalAssets).zeroFloorSub(loss).toUint192();
            enterBlocked = true;
        }

        for (uint256 i; i < ids.length; i++) {
            allocation[ids[i]] = allocation[ids[i]].zeroFloorSub(loss) + assets;

            require(allocation[ids[i]] <= absoluteCap[ids[i]], ErrorsLib.AbsoluteCapExceeded());
            require(
                relativeCap[ids[i]] == WAD
                    || allocation[ids[i]] <= uint256(_totalAssets).mulDivDown(relativeCap[ids[i]], WAD),
                ErrorsLib.RelativeCapExceeded()
            );
        }
        emit EventsLib.Allocate(msg.sender, adapter, assets, ids, loss);
    }

    /// @dev This function will automatically realize potential losses.
    function deallocate(address adapter, bytes memory data, uint256 assets) external {
        require(
            isAllocator[msg.sender] || isSentinel[msg.sender] || msg.sender == address(this), ErrorsLib.Unauthorized()
        );
        require(isAdapter[adapter], ErrorsLib.NotAdapter());

        (bytes32[] memory ids, uint256 loss) = IAdapter(adapter).deallocate(data, assets);

        if (loss > 0) {
            _totalAssets = uint256(_totalAssets).zeroFloorSub(loss).toUint192();
            enterBlocked = true;
        }

        for (uint256 i; i < ids.length; i++) {
            allocation[ids[i]] = allocation[ids[i]].zeroFloorSub(loss + assets);
        }

        SafeERC20Lib.safeTransferFrom(asset, adapter, address(this), assets);
        emit EventsLib.Deallocate(msg.sender, adapter, assets, ids, loss);
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
        require(executableAt[data] == 0, ErrorsLib.DataAlreadyPending());

        bytes4 selector = bytes4(data);
        executableAt[data] = block.timestamp + timelock[selector];
        emit EventsLib.Submit(selector, data, executableAt[data]);
    }

    modifier timelocked() {
        require(executableAt[msg.data] != 0, ErrorsLib.DataNotTimelocked());
        require(block.timestamp >= executableAt[msg.data], ErrorsLib.TimelockNotExpired());
        executableAt[msg.data] = 0;
        _;
    }

    function revoke(bytes calldata data) external {
        require(msg.sender == curator || isSentinel[msg.sender], ErrorsLib.Unauthorized());
        require(executableAt[data] != 0, ErrorsLib.DataNotTimelocked());
        executableAt[data] = 0;
        emit EventsLib.Revoke(msg.sender, bytes4(data), data);
    }

    /* EXCHANGE RATE */

    function accrueInterest() public {
        (uint256 newTotalAssets, uint256 performanceFeeShares, uint256 managementFeeShares) = accrueInterestView();
        emit EventsLib.AccrueInterest(_totalAssets, newTotalAssets, performanceFeeShares, managementFeeShares);
        _totalAssets = newTotalAssets.toUint192();
        if (performanceFeeShares != 0) createShares(performanceFeeRecipient, performanceFeeShares);
        if (managementFeeShares != 0) createShares(managementFeeRecipient, managementFeeShares);
        lastUpdate = uint64(block.timestamp);
    }

    /// @dev Returns newTotalAssets, performanceFeeShares, managementFeeShares.
    function accrueInterestView() public view returns (uint256, uint256, uint256) {
        uint256 elapsed = block.timestamp - lastUpdate;
        if (elapsed == 0) return (_totalAssets, 0, 0);

        uint256 tentativeInterestPerSecond =
            UtilsLib.controlledStaticCall(vic, abi.encodeCall(IVic.interestPerSecond, (_totalAssets, elapsed)));

        uint256 interestPerSecond = tentativeInterestPerSecond
            <= uint256(_totalAssets).mulDivDown(MAX_RATE_PER_SECOND, WAD) ? tentativeInterestPerSecond : 0;
        uint256 interest = interestPerSecond * elapsed;
        uint256 newTotalAssets = _totalAssets + interest;

        uint256 performanceFeeShares;
        uint256 managementFeeShares;
        // Note: the fee assets is subtracted from the total assets in the fee shares calculation to compensate for the
        // fact that total assets is already increased by the total interest (including the fee assets).
        // Note: `feeAssets` may be rounded down to 0 if `totalInterest * fee < WAD`.

        if (interest > 0 && performanceFee != 0 && canReceive(performanceFeeRecipient)) {
            // Note: the accrued performance fee might be smaller than this because of the management fee.
            uint256 performanceFeeAssets = interest.mulDivDown(performanceFee, WAD);
            performanceFeeShares =
                performanceFeeAssets.mulDivDown(totalSupply + 1, newTotalAssets + 1 - performanceFeeAssets);
        }
        if (managementFee != 0 && canReceive(managementFeeRecipient)) {
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

    /// @dev Returns previewed minted shares.
    function previewDeposit(uint256 assets) public view returns (uint256) {
        (uint256 newTotalAssets, uint256 performanceFeeShares, uint256 managementFeeShares) = accrueInterestView();
        uint256 newTotalSupply = totalSupply + performanceFeeShares + managementFeeShares;
        return assets.mulDivDown(newTotalSupply + 1, newTotalAssets + 1);
    }

    /// @dev Returns previewed deposited assets.
    function previewMint(uint256 shares) public view returns (uint256) {
        (uint256 newTotalAssets, uint256 performanceFeeShares, uint256 managementFeeShares) = accrueInterestView();
        uint256 newTotalSupply = totalSupply + performanceFeeShares + managementFeeShares;
        return shares.mulDivUp(newTotalAssets + 1, newTotalSupply + 1);
    }

    /// @dev Returns previewed redeemed shares.
    function previewWithdraw(uint256 assets) public view returns (uint256) {
        (uint256 newTotalAssets, uint256 performanceFeeShares, uint256 managementFeeShares) = accrueInterestView();
        uint256 newTotalSupply = totalSupply + performanceFeeShares + managementFeeShares;
        return assets.mulDivUp(newTotalSupply + 1, newTotalAssets + 1);
    }

    /// @dev Returns previewed withdrawn assets.
    function previewRedeem(uint256 shares) public view returns (uint256) {
        (uint256 newTotalAssets, uint256 performanceFeeShares, uint256 managementFeeShares) = accrueInterestView();
        uint256 newTotalSupply = totalSupply + performanceFeeShares + managementFeeShares;
        return shares.mulDivDown(newTotalAssets + 1, newTotalSupply + 1);
    }

    /* USER MAIN FUNCTIONS */

    /// @dev Returns minted shares.
    function deposit(uint256 assets, address onBehalf) external returns (uint256) {
        accrueInterest();
        uint256 shares = previewDeposit(assets);
        enter(assets, shares, onBehalf);
        return shares;
    }

    /// @dev Returns deposited assets.
    function mint(uint256 shares, address onBehalf) external returns (uint256) {
        accrueInterest();
        uint256 assets = previewMint(shares);
        enter(assets, shares, onBehalf);
        return assets;
    }

    /// @dev Internal function for deposit and mint.
    function enter(uint256 assets, uint256 shares, address onBehalf) internal {
        require(!enterBlocked, ErrorsLib.EnterBlocked());
        require(canReceive(onBehalf), ErrorsLib.CannotReceive());
        require(canSendUnderlyingAssets(msg.sender), ErrorsLib.CannotSendUnderlyingAssets());

        SafeERC20Lib.safeTransferFrom(asset, msg.sender, address(this), assets);
        createShares(onBehalf, shares);
        _totalAssets += assets.toUint192();
        if (liquidityAdapter != address(0)) {
            try this.allocate(liquidityAdapter, liquidityData, assets) {} catch {}
        }
        emit EventsLib.Deposit(msg.sender, onBehalf, assets, shares);
    }

    /// @dev Returns redeemed shares.
    function withdraw(uint256 assets, address receiver, address onBehalf) public returns (uint256) {
        accrueInterest();
        uint256 shares = previewWithdraw(assets);
        exit(assets, shares, receiver, onBehalf);
        return shares;
    }

    /// @dev Returns withdrawn assets.
    function redeem(uint256 shares, address receiver, address onBehalf) external returns (uint256) {
        accrueInterest();
        uint256 assets = previewRedeem(shares);
        exit(assets, shares, receiver, onBehalf);
        return assets;
    }

    /// @dev Internal function for withdraw and redeem.
    function exit(uint256 assets, uint256 shares, address receiver, address onBehalf) internal {
        require(canSend(onBehalf), ErrorsLib.CannotSend());
        require(canReceiveUnderlyingAssets(receiver), ErrorsLib.CannotReceiveUnderlyingAssets());

        uint256 idleAssets = IERC20(asset).balanceOf(address(this));
        if (assets > idleAssets && liquidityAdapter != address(0)) {
            this.deallocate(liquidityAdapter, liquidityData, assets - idleAssets);
        }

        if (msg.sender != onBehalf) {
            uint256 _allowance = allowance[onBehalf][msg.sender];
            if (_allowance != type(uint256).max) allowance[onBehalf][msg.sender] = _allowance - shares;
        }

        deleteShares(onBehalf, shares);
        _totalAssets -= assets.toUint192();

        SafeERC20Lib.safeTransfer(asset, receiver, assets);
        emit EventsLib.Withdraw(msg.sender, receiver, onBehalf, assets, shares);
    }

    /// @dev Returns shares withdrawn as penalty.
    /// @dev This function will automatically realize potential losses.
    function forceDeallocate(address adapter, bytes memory data, uint256 assets, address onBehalf)
        external
        returns (uint256)
    {
        this.deallocate(adapter, data, assets);

        // The penalty is taken as a withdrawal that is donated to the vault.
        uint256 penaltyAssets = assets.mulDivDown(forceDeallocatePenalty[adapter], WAD);
        uint256 shares = withdraw(penaltyAssets, address(this), onBehalf);
        emit EventsLib.ForceDeallocate(msg.sender, adapter, data, assets, onBehalf);
        return shares;
    }

    /* ERC20 */

    /// @dev Returns success (always true because reverts on failure).
    function transfer(address to, uint256 shares) external returns (bool) {
        require(to != address(0), ErrorsLib.ZeroAddress());

        require(canSend(msg.sender), ErrorsLib.CannotSend());
        require(canReceive(to), ErrorsLib.CannotReceive());

        balanceOf[msg.sender] -= shares;
        balanceOf[to] += shares;
        emit EventsLib.Transfer(msg.sender, to, shares);
        return true;
    }

    /// @dev Returns success (always true because reverts on failure).
    function transferFrom(address from, address to, uint256 shares) external returns (bool) {
        require(from != address(0), ErrorsLib.ZeroAddress());
        require(to != address(0), ErrorsLib.ZeroAddress());

        require(canSend(from), ErrorsLib.CannotSend());
        require(canReceive(to), ErrorsLib.CannotReceive());

        if (msg.sender != from) {
            uint256 _allowance = allowance[from][msg.sender];
            if (_allowance != type(uint256).max) {
                allowance[from][msg.sender] = _allowance - shares;
                emit EventsLib.AllowanceUpdatedByTransferFrom(from, msg.sender, _allowance - shares);
            }
        }

        balanceOf[from] -= shares;
        balanceOf[to] += shares;
        emit EventsLib.Transfer(from, to, shares);
        return true;
    }

    /// @dev Returns success (always true because reverts on failure).
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

    /* PERMISSION FUNCTIONS HELPERS */

    function canReceiveUnderlyingAssets(address account) public view returns (bool) {
        return receiveAssetsGate == address(0) || IReceiveAssetsGate(receiveAssetsGate).canReceiveAssets(account);
    }

    function canSendUnderlyingAssets(address account) public view returns (bool) {
        return sendAssetsGate == address(0) || ISendAssetsGate(sendAssetsGate).canSendAssets(account);
    }

    function canSend(address account) public view returns (bool) {
        return sharesGate == address(0) || ISharesGate(sharesGate).canSendShares(account);
    }

    function canReceive(address account) public view returns (bool) {
        return sharesGate == address(0) || ISharesGate(sharesGate).canReceiveShares(account);
    }
}
