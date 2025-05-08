// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.28;

import {IVaultV2, IERC20} from "./interfaces/IVaultV2.sol";
import {IAdapter} from "./interfaces/IAdapter.sol";
import {IInterestController} from "./interfaces/IInterestController.sol";

import {ErrorsLib} from "./libraries/ErrorsLib.sol";
import {EventsLib} from "./libraries/EventsLib.sol";
import "./libraries/ConstantsLib.sol";
import {MathLib} from "./libraries/MathLib.sol";
import {SafeERC20Lib} from "./libraries/SafeERC20Lib.sol";

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

    /* VAULT STORAGE */
    uint256 public totalAssets;
    uint256 public lastUpdate;

    /* CURATION AND ALLOCATION STORAGE */
    address public interestController;
    uint256 public forceReallocateToIdlePenalty;
    /// @dev Adapter is trusted to pass the expected ids when supplying assets.
    mapping(address => bool) public isAdapter;
    /// @dev Key is an abstract id, which can represent a protocol, a collateral, a duration etc.
    mapping(bytes32 => uint256) public absoluteCap;
    /// @dev Key is an abstract id, which can represent a protocol, a collateral, a duration etc.
    /// "one" is 1 WAD.
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
    uint256 public performanceFee;
    address public performanceFeeRecipient;
    /// @dev invariant: managementFee != 0 => managementFeeRecipient != address(0)
    uint256 public managementFee;
    address public managementFeeRecipient;

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

    /* CONSTRUCTOR */

    constructor(address _owner, address _asset) {
        asset = _asset;
        owner = _owner;
        lastUpdate = block.timestamp;
        timelock[IVaultV2.decreaseTimelock.selector] = TIMELOCK_CAP;
        emit EventsLib.Construction(_owner, _asset);
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

    function setInterestController(address newInterestController) external timelocked {
        interestController = newInterestController;
        emit EventsLib.SetInterestController(newInterestController);
    }

    function setIsAdapter(address account, bool newIsAdapter) external timelocked {
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

        performanceFee = newPerformanceFee;
        emit EventsLib.SetPerformanceFee(newPerformanceFee);
    }

    function setManagementFee(uint256 newManagementFee) external timelocked {
        require(newManagementFee <= MAX_MANAGEMENT_FEE, ErrorsLib.FeeTooHigh());
        require(managementFeeRecipient != address(0) || newManagementFee == 0, ErrorsLib.FeeInvariantBroken());

        accrueInterest();

        managementFee = newManagementFee;
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

    function decreaseAbsoluteCap(bytes32 id, uint256 newAbsoluteCap) external {
        require(msg.sender == curator || isSentinel[msg.sender], ErrorsLib.Unauthorized());
        require(newAbsoluteCap <= absoluteCap[id], ErrorsLib.AbsoluteCapNotDecreasing());

        absoluteCap[id] = newAbsoluteCap;
        emit EventsLib.DecreaseAbsoluteCap(id, newAbsoluteCap);
    }

    function increaseRelativeCap(bytes32 id, uint256 newRelativeCap) external timelocked {
        require(newRelativeCap <= WAD, ErrorsLib.RelativeCapAboveOne());
        require(newRelativeCap >= relativeCap(id), ErrorsLib.RelativeCapNotIncreasing());

        if (relativeCap(id) < WAD && newRelativeCap == WAD) {
            uint256 i;
            while (idsWithRelativeCap[i] != id) i++;
            idsWithRelativeCap[i] = idsWithRelativeCap[idsWithRelativeCap.length - 1];
            idsWithRelativeCap.pop();
        }

        oneMinusRelativeCap[id] = WAD - newRelativeCap;

        emit EventsLib.IncreaseRelativeCap(id, newRelativeCap);
    }

    function decreaseRelativeCap(bytes32 id, uint256 newRelativeCap) external timelocked {
        require(newRelativeCap > 0, ErrorsLib.RelativeCapZero());
        require(newRelativeCap <= relativeCap(id), ErrorsLib.RelativeCapNotDecreasing());
        if (newRelativeCap < WAD) {
            require(allocation[id] <= totalAssets.mulDivDown(newRelativeCap, WAD), ErrorsLib.RelativeCapExceeded());
        }

        if (relativeCap(id) == WAD && newRelativeCap < WAD) idsWithRelativeCap.push(id);

        oneMinusRelativeCap[id] = WAD - newRelativeCap;

        emit EventsLib.DecreaseRelativeCap(id, newRelativeCap);
    }

    function setForceReallocateToIdlePenalty(uint256 newForceReallocateToIdlePenalty) external timelocked {
        require(newForceReallocateToIdlePenalty <= MAX_FORCE_REALLOCATE_TO_IDLE_PENALTY, ErrorsLib.PenaltyTooHigh());
        forceReallocateToIdlePenalty = newForceReallocateToIdlePenalty;
        emit EventsLib.SetForceReallocateToIdlePenalty(newForceReallocateToIdlePenalty);
    }

    /* ALLOCATOR ACTIONS */

    function reallocateFromIdle(address adapter, bytes memory data, uint256 amount) external {
        require(isAllocator[msg.sender] || msg.sender == address(this), ErrorsLib.NotAllocator());
        require(isAdapter[adapter], ErrorsLib.NotAdapter());

        SafeERC20Lib.safeTransfer(asset, adapter, amount);
        bytes32[] memory ids = IAdapter(adapter).allocateIn(data, amount);

        for (uint256 i; i < ids.length; i++) {
            allocation[ids[i]] += amount;

            require(allocation[ids[i]] <= absoluteCap[ids[i]], ErrorsLib.AbsoluteCapExceeded());
            if (relativeCap(ids[i]) < WAD) {
                require(
                    allocation[ids[i]] <= totalAssets.mulDivDown(relativeCap(ids[i]), WAD),
                    ErrorsLib.RelativeCapExceeded()
                );
            }
        }
        emit EventsLib.ReallocateFromIdle(msg.sender, adapter, amount, ids);
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
        emit EventsLib.ReallocateToIdle(msg.sender, adapter, amount, ids);
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
        totalAssets = newTotalAssets;
        if (performanceFeeShares != 0) createShares(performanceFeeRecipient, performanceFeeShares);
        if (managementFeeShares != 0) createShares(managementFeeRecipient, managementFeeShares);
        lastUpdate = block.timestamp;
        emit EventsLib.AccrueInterest(newTotalAssets, performanceFeeShares, managementFeeShares);
    }

    function accrueInterestView() public view returns (uint256, uint256, uint256) {
        uint256 elapsed = block.timestamp - lastUpdate;
        if (elapsed == 0) return (totalAssets, 0, 0);
        uint256 interestPerSecond = IInterestController(interestController).interestPerSecond(totalAssets, elapsed);
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

    function enter(uint256 assets, uint256 shares, address receiver) internal {
        SafeERC20Lib.safeTransferFrom(asset, msg.sender, address(this), assets);
        createShares(receiver, shares);
        totalAssets += assets;
        if (liquidityAdapter != address(0)) {
            try this.reallocateFromIdle(liquidityAdapter, liquidityData, assets) {} catch {}
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
        uint256 idleAssets = IERC20(asset).balanceOf(address(this));
        if (assets > idleAssets && liquidityAdapter != address(0)) {
            this.reallocateToIdle(liquidityAdapter, liquidityData, assets - idleAssets);
        }

        if (msg.sender != onBehalf) {
            uint256 _allowance = allowance[onBehalf][msg.sender];
            if (_allowance != type(uint256).max) allowance[onBehalf][msg.sender] = _allowance - shares;
        }

        deleteShares(onBehalf, shares);
        totalAssets -= assets;

        for (uint256 i; i < idsWithRelativeCap.length; i++) {
            bytes32 id = idsWithRelativeCap[i];
            if (relativeCap(id) < WAD) {
                require(allocation[id] <= totalAssets.mulDivDown(relativeCap(id), WAD), ErrorsLib.RelativeCapExceeded());
            }
        }

        SafeERC20Lib.safeTransfer(asset, receiver, assets);
        emit EventsLib.Withdraw(msg.sender, receiver, onBehalf, assets, shares);
    }

    /// @dev Loop to make the relative cap check at the end.
    function forceReallocateToIdle(
        address[] memory adapters,
        bytes[] memory data,
        uint256[] memory assets,
        address onBehalf
    ) external returns (uint256) {
        require(adapters.length == data.length && adapters.length == assets.length, ErrorsLib.InvalidInputLength());
        uint256 total;
        for (uint256 i; i < adapters.length; i++) {
            this.reallocateToIdle(adapters[i], data[i], assets[i]);
            total += assets[i];
        }

        // The penalty is taken as a withdrawal that is donated to the vault.
        uint256 shares = withdraw(total.mulDivDown(forceReallocateToIdlePenalty, WAD), address(this), onBehalf);
        emit EventsLib.ForceReallocateToIdle(msg.sender, onBehalf, total);
        return shares;
    }

    /* ERC20 */

    function transfer(address to, uint256 amount) external returns (bool) {
        require(to != address(0), ErrorsLib.ZeroAddress());
        balanceOf[msg.sender] -= amount;
        balanceOf[to] += amount;
        emit EventsLib.Transfer(msg.sender, to, amount);
        return true;
    }

    function transferFrom(address from, address to, uint256 amount) external returns (bool) {
        require(from != address(0), ErrorsLib.ZeroAddress());
        require(to != address(0), ErrorsLib.ZeroAddress());

        if (msg.sender != from) {
            uint256 _allowance = allowance[from][msg.sender];
            if (_allowance != type(uint256).max) allowance[from][msg.sender] = _allowance - amount;
        }

        balanceOf[from] -= amount;
        balanceOf[to] += amount;
        emit EventsLib.Transfer(from, to, amount);
        emit EventsLib.TransferFrom(msg.sender, from, to, amount);
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

        uint256 nonce = nonces[_owner]++;
        bytes32 hashStruct = keccak256(abi.encode(PERMIT_TYPEHASH, _owner, spender, value, nonce, deadline));
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", DOMAIN_SEPARATOR(), hashStruct));
        address recoveredAddress = ecrecover(digest, v, r, s);
        require(recoveredAddress != address(0) && recoveredAddress == _owner, ErrorsLib.InvalidSigner());

        allowance[_owner][spender] = value;
        emit EventsLib.Approval(_owner, spender, value);
        emit EventsLib.Permit(_owner, spender, value, nonce, deadline);
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
